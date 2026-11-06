//! Deterministic pace coaching. Calendar conversion remains with the Swift host;
//! this core receives one immutable batch and performs no I/O or account access.
use std::cmp::Ordering;

const NONE: u32 = 0;
const ON_TRACK: u32 = 1;
const HITS_LIMIT: u32 = 2;
const SLOW_DOWN: u32 = 3;
const INVALID: u32 = 4;
const NEEDS_HISTORY: u32 = 5;

#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct PacePoint {
    /// Foundation reference-date seconds, preserving Date comparison precision.
    pub timestamp: f64,
    /// The old regression explicitly converted dates to Unix seconds.
    pub regression_timestamp: f64,
    pub fraction: f64,
    /// The host's Date.timeIntervalSince(previous), before Unix conversion.
    pub previous_interval: f64,
    pub local_hour: i32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct PaceResult {
    pub kind: u32,
    pub hours: i64,
    pub minutes: i64,
    pub remaining_percent: f64,
}

#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct PaceRequest {
    pub current: f64,
    pub now: f64,
    pub reset: f64,
    pub has_reset: u32,
    pub current_hour: i32,
    pub include_history: u32,
}

impl PaceResult {
    const fn kind(kind: u32) -> Self {
        Self {
            kind,
            hours: 0,
            minutes: 0,
            remaining_percent: 0.0,
        }
    }
    fn on_track(current: f64) -> Self {
        Self {
            remaining_percent: 100.0 - current,
            ..Self::kind(ON_TRACK)
        }
    }
}

type RankedPoint = (usize, PacePoint);

fn chronological(a: &RankedPoint, b: &RankedPoint) -> Ordering {
    // Inputs are finite. Source position reproduces Swift's stable sort for
    // equal timestamps, including -0.0/0.0, without reordering history pairs.
    a.1.timestamp
        .partial_cmp(&b.1.timestamp)
        .unwrap()
        .then_with(|| a.0.cmp(&b.0))
}

pub fn calculate(
    points: &[PacePoint],
    current: f64,
    now: f64,
    reset: Option<f64>,
    current_hour: i32,
) -> PaceResult {
    calculate_stage(points, current, now, reset, Some(current_hour))
}

fn calculate_stage(
    points: &[PacePoint],
    current: f64,
    now: f64,
    reset: Option<f64>,
    current_hour: Option<i32>,
) -> PaceResult {
    let Some(reset) = reset else {
        return PaceResult::kind(NONE);
    };
    if !current.is_finite()
        || !now.is_finite()
        || !reset.is_finite()
        || current_hour.is_some_and(|hour| !(0..24).contains(&hour))
        || points.iter().any(|point| {
            !point.timestamp.is_finite()
                || !point.regression_timestamp.is_finite()
                || !point.fraction.is_finite()
                || !point.previous_interval.is_finite()
                || (current_hour.is_some() && !(0..24).contains(&point.local_hour))
        })
    {
        return PaceResult::kind(INVALID);
    }
    if reset <= now {
        return PaceResult::kind(NONE);
    }
    let since = now - 7200.0;
    let threshold = current / 100.0 + 0.20;
    let cutoff = points
        .iter()
        .copied()
        .enumerate()
        .filter(|(_, point)| point.timestamp >= since && point.fraction > threshold)
        .max_by(chronological);

    // Only five recent points affect regression. Two linear passes replace a
    // full-history filter/sort/copy, with at most six temporary recent entries.
    let mut recent: Vec<RankedPoint> = Vec::with_capacity(6);
    for sample in points.iter().copied().enumerate() {
        if sample.1.timestamp < since
            || cutoff
                .as_ref()
                .is_some_and(|cutoff| chronological(&sample, cutoff).is_le())
        {
            continue;
        }
        let at = recent.partition_point(|point| chronological(point, &sample).is_le());
        recent.insert(at, sample);
        if recent.len() > 5 {
            recent.remove(0);
        }
    }
    if recent.len() < 2 {
        return PaceResult::kind(NONE);
    }
    let origin = recent[0].1.regression_timestamp;
    let n = recent.len() as f64;
    let (mut sum_t, mut sum_u, mut sum_tu, mut sum_tt) = (0.0, 0.0, 0.0, 0.0);
    for (_, point) in recent {
        let t = point.regression_timestamp - origin;
        let u = point.fraction * 100.0;
        sum_t += t;
        sum_u += u;
        sum_tu += t * u;
        sum_tt += t * t;
    }
    let denominator = n * sum_tt - sum_t * sum_t;
    if !denominator.is_finite() {
        return PaceResult::kind(INVALID);
    }
    if denominator.abs() <= 1e-10 {
        return PaceResult::on_track(current);
    }
    let velocity = (n * sum_tu - sum_t * sum_u) / denominator * 3600.0;
    if !velocity.is_finite() {
        return PaceResult::kind(INVALID);
    }
    if velocity <= 0.0 {
        return PaceResult::on_track(current);
    }

    // The host avoids all Calendar hour conversions for nil/on-track paths.
    // A positive slope requests one final batch with historical local hours.
    let Some(current_hour) = current_hour else {
        return PaceResult::kind(NEEDS_HISTORY);
    };

    let mut rates = Vec::new();
    for pair in points.windows(2) {
        let (previous, point) = (pair[0], pair[1]);
        if previous.local_hour != current_hour || point.local_hour != current_hour {
            continue;
        }
        let dt = point.previous_interval;
        let du = (point.fraction - previous.fraction) * 100.0;
        if dt <= 0.0 || du <= 0.0 {
            continue;
        }
        let rate = du / dt * 3600.0;
        if !rate.is_finite() {
            return PaceResult::kind(INVALID);
        }
        rates.push(rate);
    }
    if rates.len() >= 3 {
        let count = rates.len();
        let (lower, upper, _) =
            rates.select_nth_unstable_by(count / 2, |a, b| a.partial_cmp(b).unwrap());
        let median = if count.is_multiple_of(2) {
            (lower.iter().copied().reduce(f64::max).unwrap() + *upper) / 2.0
        } else {
            *upper
        };
        if median > 0.0 && velocity > 1.5 * median {
            return PaceResult::kind(SLOW_DOWN);
        }
    }
    let total_minutes = ((100.0 - current) / velocity * 60.0).trunc();
    // Unlike an unchecked Swift Int conversion, invalid/extreme arithmetic must
    // not trap the menu-bar process. 2^63 is not representable as an i64.
    if !total_minutes.is_finite()
        || !(-9_223_372_036_854_775_808.0..9_223_372_036_854_775_808.0).contains(&total_minutes)
    {
        return PaceResult::kind(INVALID);
    }
    let total_minutes = total_minutes as i64;
    PaceResult {
        hours: total_minutes / 60,
        minutes: total_minutes % 60,
        ..PaceResult::kind(HITS_LIMIT)
    }
}

// SAFETY: This uniquely prefixed symbol has one definition in the linked app.
#[unsafe(no_mangle)]
pub extern "C" fn pace_core_abi_version() -> u32 {
    1
}

/// Calculates one batch without taking ownership of caller memory.
///
/// # Safety
/// For nonzero `count`, `points` must reference `count` initialized, aligned
/// `PacePoint` entries, readable and unmodified until this call returns. A null
/// pointer with count zero is supported. This function retains no pointers.
// SAFETY: The exported symbol is uniquely prefixed; the header matches repr(C).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn pace_core_calculate(
    points: *const PacePoint,
    count: usize,
    request: PaceRequest,
) -> PaceResult {
    if request.has_reset > 1
        || request.include_history > 1
        || count > isize::MAX as usize / std::mem::size_of::<PacePoint>()
        || (count > 0 && points.is_null())
    {
        return PaceResult::kind(INVALID);
    }
    let points = if count == 0 {
        &[]
    } else {
        // SAFETY: The caller guarantees this readable slice for the call;
        // null and impossible slice lengths were rejected above.
        unsafe { std::slice::from_raw_parts(points, count) }
    };
    calculate_stage(
        points,
        request.current,
        request.now,
        (request.has_reset == 1).then_some(request.reset),
        (request.include_history == 1).then_some(request.current_hour),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn point(timestamp: f64, fraction: f64) -> PacePoint {
        PacePoint {
            timestamp,
            regression_timestamp: timestamp,
            fraction,
            previous_interval: 0.0,
            local_hour: 12,
        }
    }

    #[test]
    fn missing_expired_or_insufficient_history_is_none() {
        let points = [point(1000.0, 0.5)];
        assert_eq!(calculate(&points, 50.0, 1000.0, None, 12).kind, NONE);
        assert_eq!(
            calculate(&points, 50.0, 1000.0, Some(1000.0), 12).kind,
            NONE
        );
        assert_eq!(
            calculate(&points, 50.0, 1000.0, Some(2000.0), 12).kind,
            NONE
        );
    }

    #[test]
    fn known_slope_projects_two_hours() {
        let result = calculate(
            &[point(1000.0, 0.5), point(2800.0, 0.6)],
            60.0,
            2800.0,
            Some(10000.0),
            12,
        );
        assert_eq!(
            (result.kind, result.hours, result.minutes),
            (HITS_LIMIT, 2, 0)
        );
    }

    #[test]
    fn duplicate_timestamps_and_non_positive_velocity_are_on_track() {
        for points in [
            [point(1000.0, 0.5), point(1000.0, 0.6)],
            [point(1000.0, 0.5), point(2000.0, 0.4)],
        ] {
            assert_eq!(
                calculate(&points, 60.0, 2800.0, Some(10000.0), 12),
                PaceResult::on_track(60.0)
            );
        }
    }

    #[test]
    fn reset_cutoff_uses_stable_source_order_for_equal_timestamps() {
        let points = [point(1000.0, 0.9), point(1000.0, 0.1), point(2000.0, 0.2)];
        assert_eq!(
            calculate(&points, 20.0, 2000.0, Some(10000.0), 12).kind,
            HITS_LIMIT
        );
        let reversed = [points[1], points[0], points[2]];
        assert_eq!(
            calculate(&reversed, 20.0, 2000.0, Some(10000.0), 12).kind,
            NONE
        );
    }

    #[test]
    fn invalid_numbers_and_ffi_inputs_fail_without_panicking() {
        assert_eq!(
            calculate(&[point(1000.0, f64::NAN)], 50.0, 2000.0, Some(3000.0), 12).kind,
            INVALID
        );
        // SAFETY: Null is rejected for nonempty inputs and supported for empty ones.
        unsafe {
            let request = PaceRequest {
                current: 50.0,
                now: 1000.0,
                reset: 2000.0,
                has_reset: 1,
                current_hour: 12,
                include_history: 1,
            };
            assert_eq!(
                pace_core_calculate(std::ptr::null(), 1, request).kind,
                INVALID
            );
            assert_eq!(pace_core_calculate(std::ptr::null(), 0, request).kind, NONE);
        }
    }

    #[test]
    fn positive_projection_requests_history_but_flat_projection_does_not() {
        let positive = [point(1000.0, 0.5), point(2000.0, 0.6)];
        assert_eq!(
            calculate_stage(&positive, 60.0, 2000.0, Some(3000.0), None).kind,
            NEEDS_HISTORY
        );
        let flat = [point(1000.0, 0.5), point(2000.0, 0.5)];
        assert_eq!(
            calculate_stage(&flat, 50.0, 2000.0, Some(3000.0), None).kind,
            ON_TRACK
        );
    }
}

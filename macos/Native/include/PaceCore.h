#ifndef CLAUDE_USAGE_PACE_CORE_H
#define CLAUDE_USAGE_PACE_CORE_H

#include <stddef.h>
#include <stdint.h>

#define PACE_CORE_NONE 0u
#define PACE_CORE_ON_TRACK 1u
#define PACE_CORE_HITS_LIMIT 2u
#define PACE_CORE_SLOW_DOWN 3u
#define PACE_CORE_INVALID 4u
#define PACE_CORE_NEEDS_HISTORY 5u

typedef struct {
    /* Ordering/window comparisons use Foundation reference-date seconds. */
    double timestamp;
    /* Preserve the legacy regression's explicit Unix-seconds conversion. */
    double regression_timestamp;
    double fraction;
    /* Foundation Date interval from the previous point in source order. */
    double previous_interval;
    int32_t local_hour;
} PaceCorePoint;

typedef struct {
    uint32_t kind;
    int64_t hours;
    int64_t minutes;
    double remaining_percent;
} PaceCoreResult;

typedef struct {
    double current;
    double now;
    double reset;
    uint32_t has_reset;
    int32_t current_hour;
    uint32_t include_history;
} PaceCoreRequest;

#ifdef __cplusplus
extern "C" {
#endif

uint32_t pace_core_abi_version(void);
/* Nonempty points must be an aligned, readable array for the duration of this
 * call. No pointer is retained. Empty arrays may use a null pointer. */
/* now/reset use Foundation reference-date seconds. include_history=0 performs
 * projection only: NEEDS_HISTORY requests a second call with local hours and
 * include_history=1. Other results are final; unknown presence/mode flags fail. */
PaceCoreResult pace_core_calculate(const PaceCorePoint *points, size_t count,
                                  PaceCoreRequest request);

#ifdef __cplusplus
}
#endif

#endif

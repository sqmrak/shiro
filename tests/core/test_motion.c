#include "shiro_motion.h"

#include <math.h>
#include <stdio.h>

static int failures;

#define CHECK(condition) do { if (!(condition)) { fprintf(stderr, "test_motion: %s:%d: %s\n", __FILE__, __LINE__, #condition); ++failures; } } while (0)

int main(void) {
    static const shiro_motion_curve curves[] = {
        SHIRO_MOTION_ENTER, SHIRO_MOTION_EXIT, SHIRO_MOTION_DISMISS, SHIRO_MOTION_POPUP_ENTER,
        SHIRO_MOTION_POPUP_EXIT, SHIRO_MOTION_LIST_MOVE, SHIRO_MOTION_SCREEN_IN,
        SHIRO_MOTION_SCREEN_OUT, SHIRO_MOTION_SCREEN_UNDER, SHIRO_MOTION_SPRING,
        SHIRO_MOTION_WOBBLE, SHIRO_MOTION_SETTLE
    };
    /* the first nine never go backwards, the springs do */
    const size_t monotonic = 9;
    for (size_t i = 0; i < sizeof curves / sizeof curves[0]; ++i) {
        shiro_motion_curve curve = curves[i];
        double duration = shiro_motion_duration(curve);
        CHECK(duration > 0.1 && duration < 1.0);
        /* the ends are exact, and a time outside the range or not a number is held to them */
        CHECK(shiro_motion_progress(curve, 0.0) == 0.0);
        CHECK(shiro_motion_progress(curve, 1.0) == 1.0);
        CHECK(shiro_motion_progress(curve, -3.0) == 0.0);
        CHECK(shiro_motion_progress(curve, 7.0) == 1.0);
        CHECK(shiro_motion_progress(curve, NAN) == 0.0);
        CHECK(shiro_motion_progress(curve, INFINITY) == 1.0);
        double previous = 0.0;
        for (int step = 1; step <= 100; ++step) {
            double value = shiro_motion_progress(curve, step / 100.0);
            CHECK(isfinite(value));
            CHECK(value > -0.05 && value < 1.5);
            if (i < monotonic) {
                CHECK(value >= previous - 1e-9);
                previous = value;
            }
        }
    }
    /* the durations of the android build, in milliseconds */
    CHECK(fabs(shiro_motion_duration(SHIRO_MOTION_ENTER) - 0.32) < 1e-9);
    CHECK(fabs(shiro_motion_duration(SHIRO_MOTION_EXIT) - 0.18) < 1e-9);
    CHECK(fabs(shiro_motion_duration(SHIRO_MOTION_POPUP_ENTER) - 0.34) < 1e-9);
    CHECK(fabs(shiro_motion_duration(SHIRO_MOTION_SCREEN_IN) - 0.24) < 1e-9);
    /* a decelerating screen is past halfway at half its time, an accelerating one is not */
    CHECK(shiro_motion_progress(SHIRO_MOTION_SCREEN_IN, 0.5) > 0.7);
    CHECK(shiro_motion_progress(SHIRO_MOTION_SCREEN_OUT, 0.5) < 0.3);
    CHECK(fabs(shiro_motion_progress(SHIRO_MOTION_SCREEN_UNDER, 0.5) - 0.5) < 1e-9);
    /* the spring passes its target by about a tenth, the wobble by more and swings back
       past it again, and the settle stays nearly inside its track */
    {
        double wobble_peak = 0.0;
        double spring_peak = 0.0;
        double settle_peak = 0.0;
        int crossings = 0;
        int above = 0;
        for (int step = 1; step < 1000; ++step) {
            double t = step / 1000.0;
            double w = shiro_motion_progress(SHIRO_MOTION_WOBBLE, t);
            double s = shiro_motion_progress(SHIRO_MOTION_SPRING, t);
            double e = shiro_motion_progress(SHIRO_MOTION_SETTLE, t);
            if (w > wobble_peak) wobble_peak = w;
            if (s > spring_peak) spring_peak = s;
            if (e > settle_peak) settle_peak = e;
            if ((w > 1.0) != above) {
                ++crossings;
                above = w > 1.0;
            }
        }
        CHECK(wobble_peak > 1.2 && wobble_peak < 1.45);
        CHECK(spring_peak > 1.04 && spring_peak < 1.15);
        CHECK(settle_peak > 1.0 && settle_peak < 1.06);
        CHECK(crossings >= 3);
    }
    CHECK(shiro_motion_duration((shiro_motion_curve)99) == 0.0);
    CHECK(shiro_motion_progress((shiro_motion_curve)99, 0.5) == 0.0);
    if (failures) return 1;
    puts("motion: curve ends, bounds, monotonic curves, android durations, spring and wobble overshoot passed");
    return 0;
}

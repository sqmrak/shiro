#include "shiro_motion.h"

#include <math.h>

static double cubic(double t, double first, double second) {
    double inverse = 1.0 - t;
    return 3.0 * inverse * inverse * t * first + 3.0 * inverse * t * t * second + t * t * t;
}

/* the cubic bezier with the end points (0, 0) and (1, 1). x has no closed form,
   so it is solved by bisection */
static double bezier(double time, double x1, double y1, double x2, double y2) {
    double lower = 0.0;
    double upper = 1.0;
    for (int i = 0; i < 32; ++i) {
        double middle = (lower + upper) * 0.5;
        if (cubic(middle, x1, x2) < time) lower = middle;
        else upper = middle;
    }
    return cubic((lower + upper) * 0.5, y1, y2);
}

/* a damped spring of unit mass released at rest. the damping ratio is below 1,
   so the swing oscillates */
static double spring(double seconds, double stiffness, double damping) {
    double frequency = sqrt(stiffness);
    double decay = frequency * damping;
    double oscillation = frequency * sqrt(1.0 - damping * damping);
    return 1.0 - exp(-decay * seconds) *
        (cos(oscillation * seconds) + decay / oscillation * sin(oscillation * seconds));
}

double shiro_motion_duration(shiro_motion_curve curve) {
    switch (curve) {
    case SHIRO_MOTION_ENTER: return 0.32;
    case SHIRO_MOTION_EXIT: return 0.18;
    case SHIRO_MOTION_DISMISS: return 0.20;
    case SHIRO_MOTION_POPUP_ENTER: return 0.34;
    case SHIRO_MOTION_POPUP_EXIT: return 0.20;
    case SHIRO_MOTION_LIST_MOVE: return 0.25;
    case SHIRO_MOTION_SPRING: return 0.48;
    case SHIRO_MOTION_WOBBLE: return 0.56;
    case SHIRO_MOTION_SETTLE: return 0.38;
    case SHIRO_MOTION_SCREEN_IN: return 0.24;
    case SHIRO_MOTION_SCREEN_OUT: return 0.20;
    case SHIRO_MOTION_SCREEN_UNDER: return 0.24;
    }
    return 0.0;
}

double shiro_motion_progress(shiro_motion_curve curve, double time) {
    double duration = shiro_motion_duration(curve);
    if (duration == 0.0) return 0.0;
    if (!(time > 0.0)) return 0.0;
    if (time >= 1.0) return 1.0;
    switch (curve) {
    case SHIRO_MOTION_ENTER: return bezier(time, 0.23, 1.0, 0.32, 1.0);
    case SHIRO_MOTION_EXIT: return bezier(time, 0.42, 0.0, 1.0, 1.0);
    case SHIRO_MOTION_DISMISS: return 1.0 - (1.0 - time) * (1.0 - time);
    case SHIRO_MOTION_POPUP_ENTER: return bezier(time, 0.05, 0.7, 0.1, 1.0);
    case SHIRO_MOTION_POPUP_EXIT: return bezier(time, 0.3, 0.0, 0.8, 0.15);
    case SHIRO_MOTION_LIST_MOVE: return bezier(time, 0.19919473, 0.010644531, 0.27920938, 0.9102539);
    /* a spring is stretched by its value at the end of the duration, so the last
       sample is exactly 1 */
    case SHIRO_MOTION_SPRING: return spring(time * duration, 650.0, 0.6) / spring(duration, 650.0, 0.6);
    case SHIRO_MOTION_WOBBLE: return spring(time * duration, 520.0, 0.38) / spring(duration, 520.0, 0.38);
    case SHIRO_MOTION_SETTLE: return spring(time * duration, 700.0, 0.72) / spring(duration, 700.0, 0.72);
    /* the decelerate, accelerate and accelerate-decelerate interpolators of android */
    case SHIRO_MOTION_SCREEN_IN: return 1.0 - (1.0 - time) * (1.0 - time);
    case SHIRO_MOTION_SCREEN_OUT: return time * time;
    case SHIRO_MOTION_SCREEN_UNDER: return cos((time + 1.0) * 3.14159265358979323846) * 0.5 + 0.5;
    }
    return 0.0;
}

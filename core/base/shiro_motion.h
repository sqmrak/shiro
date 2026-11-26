#ifndef SHIRO_MOTION_H
#define SHIRO_MOTION_H

#ifdef __cplusplus
extern "C" {
#endif

/* the curves of the interface, the same numbers as the android build of shiro (Motion.java and the
   screen transitions of its res/anim). time and progress are fractions of the duration, and the
   progress of a spring passes 1 on its way and ends at exactly 1 */
typedef enum shiro_motion_curve {
    /* a view that arrives: ease out quint, 320 ms */
    SHIRO_MOTION_ENTER,
    /* a view that leaves: ease in, 180 ms */
    SHIRO_MOTION_EXIT,
    /* a card that goes away starts leaving at once, 200 ms */
    SHIRO_MOTION_DISMISS,
    /* popups and sheets, the emphasized pair of material 3: 340 ms in, 200 ms out */
    SHIRO_MOTION_POPUP_ENTER,
    SHIRO_MOTION_POPUP_EXIT,
    /* rows and cards that change place, 250 ms */
    SHIRO_MOTION_LIST_MOVE,
    /* a spring that overshoots by a tenth and settles in one swing, 480 ms */
    SHIRO_MOTION_SPRING,
    /* the loose spring of a sticker or a released button: two visible wobbles, 560 ms */
    SHIRO_MOTION_WOBBLE,
    /* a thumb that settles with a barely visible overshoot, 380 ms */
    SHIRO_MOTION_SETTLE,
    /* a screen that comes in over the one below: decelerate, 240 ms */
    SHIRO_MOTION_SCREEN_IN,
    /* a screen that goes away to the side: accelerate, 200 ms */
    SHIRO_MOTION_SCREEN_OUT,
    /* the screen underneath, pushed back and returning: accelerate then decelerate, 240 ms */
    SHIRO_MOTION_SCREEN_UNDER
} shiro_motion_curve;

/* seconds, zero for a curve that does not exist */
double shiro_motion_duration(shiro_motion_curve curve);
/* the progress at a time between 0 and 1, exactly 0 at 0 and exactly 1 at 1. a
   time outside the range or not a number is held to its end */
double shiro_motion_progress(shiro_motion_curve curve, double time);

#ifdef __cplusplus
}
#endif

#endif

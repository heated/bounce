#ifndef Constants_h
#define Constants_h

/// Can be challenging to find stable configurations.

#define TARGET_BALL_C 40000
#define width 1366.0f
#define height 768.0f
#define ballDiam 4.0f
#define ballRad (ballDiam / 2)
#define maxX (width - ballDiam)
#define maxY (height - ballDiam)
#define gravity .003f
#define friction .0f //.0025
#define wallForce .5f
#define collForce .02f
#define collFriction .007f
#define ballSpeed .6f
#define tileSlots 6

#endif /* Constants_h */

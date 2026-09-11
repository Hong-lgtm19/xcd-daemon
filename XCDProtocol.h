/*
 * XCDProtocol.h — 电脑端 <-> iPhone daemon 控制通道协议定义
 */

#ifndef XCDProtocol_h
#define XCDProtocol_h

// ---- 端口 ----
#define XCD_VIDEO_PORT   23456
#define XCD_CONTROL_PORT 23458

// ---- 消息类型 ----
typedef enum : uint8_t {
    XCDMsgHello       = 0x10,
    XCDMsgHelloAck    = 0x11,
    XCDMsgPing        = 0x12,
    XCDMsgPong        = 0x13,

    XCDMsgTouchDown   = 0x01,
    XCDMsgTouchMove   = 0x02,
    XCDMsgTouchUp     = 0x03,
    XCDMsgTouchCancel = 0x04,

    XCDMsgSwipe       = 0x06,
    XCDMsgScroll      = 0x07,

    XCDMsgKeyChar     = 0x20,
    XCDMsgKeyAction   = 0x21,

    XCDMsgButton      = 0x30,
} XCDMsgType;

typedef enum : uint16_t {
    XCDKeyHome        = 0x01,
    XCDKeyPower       = 0x02,
    XCDKeyVolumeUp    = 0x03,
    XCDKeyVolumeDown  = 0x04,
    XCDKeyBack        = 0x05,
    XCDKeyScreenshot  = 0x06,
} XCDKeyCode;

#pragma pack(push, 1)

typedef struct {
    uint8_t  type;
} xcd_msg_head_t;

typedef struct {
    uint8_t  type;
    uint8_t  touch_id;
    float    x;
    float    y;
} xcd_touch_t;

typedef struct {
    uint8_t  type;
    float    x1, y1;
    float    x2, y2;
    float    duration;
} xcd_swipe_t;

typedef struct {
    uint8_t  type;
    float    x, y;
    float    dy;
} xcd_scroll_t;

typedef struct {
    uint8_t  type;
    uint16_t code;
    uint8_t  down;
} xcd_key_t;

typedef struct {
    uint8_t  type;
    uint16_t screen_w;
    uint16_t screen_h;
    uint32_t max_fps;
} xcd_hello_t;

#pragma pack(pop)

#endif

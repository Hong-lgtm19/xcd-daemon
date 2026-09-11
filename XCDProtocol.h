/*
 * XCDProtocol.h — 电脑端 <-> iPhone daemon 控制通道协议定义
 * 两端共用同一份常量。视频通道为独立 TCP，裸 H.264 Annex-B 流。
 *
 * 传输：iPhone daemon 通过 usbmuxd 在 USB 上暴露两个内部端口：
 *   - 视频端口 23456：iPhone -> 电脑，单向，裸 H.264 (Annex-B, 含 SPS/PPS)
 *   - 控制端口 23457：双向，下列二进制消息（小端序）
 *
 * 坐标约定：所有触摸坐标为归一化 float [0.0, 1.0]，
 * daemon 收到后乘以屏幕物理分辨率，与方向无关。
 */

#ifndef XCDProtocol_h
#define XCDProtocol_h

// ---- 端口 ----
#define XCD_VIDEO_PORT   23456
#define XCD_CONTROL_PORT 23457

// ---- 消息类型 ----
typedef enum : uint8_t {
    // 握手 / 心跳
    XCDMsgHello       = 0x10,  // 服务器->客户端: 屏幕宽高
    XCDMsgHelloAck    = 0x11,  // 客户端->服务器: 确认
    XCDMsgPing        = 0x12,
    XCDMsgPong        = 0x13,

    // 触摸（多点：id 0..9）
    XCDMsgTouchDown   = 0x01,
    XCDMsgTouchMove   = 0x02,
    XCDMsgTouchUp     = 0x03,
    XCDMsgTouchCancel = 0x04,

    // 手势 / 滚轮
    XCDMsgSwipe       = 0x06,  // 两点间滑动
    XCDMsgScroll      = 0x07,  // 滚轮 dy

    // 键盘
    XCDMsgKeyChar     = 0x20,  // 可打印字符（UTF-8）
    XCDMsgKeyAction   = 0x21,  // 特殊键（Home/Power/音量/方向）

    // 设备按键
    XCDMsgButton      = 0x30,  // home / power / volup / voldown
} XCDMsgType;

// XCDMsgKeyAction / XCDMsgButton 的按键码
typedef enum : uint16_t {
    XCDKeyHome        = 0x01,
    XCDKeyPower       = 0x02,
    XCDKeyVolumeUp    = 0x03,
    XCDKeyVolumeDown  = 0x04,
    XCDKeyBack        = 0x05,  // iOS 无返回键，映射为 Home 辅助
    XCDKeyScreenshot  = 0x06,
} XCDKeyCode;

#pragma pack(push, 1)

typedef struct {
    uint8_t  type;
} xcd_msg_head_t;

typedef struct {
    uint8_t  type;       // XCDMsgTouchDown/Move/Up
    uint8_t  touch_id;
    float    x;          // 归一化 [0,1]
    float    y;
} xcd_touch_t;

typedef struct {
    uint8_t  type;       // XCDMsgSwipe
    float    x1, y1;
    float    x2, y2;
    float    duration;   // 秒
} xcd_swipe_t;

typedef struct {
    uint8_t  type;       // XCDMsgScroll
    float    x, y;
    float    dy;
} xcd_scroll_t;

typedef struct {
    uint8_t  type;       // XCDMsgKeyAction / XCDMsgButton
    uint16_t code;
    uint8_t  down;       // 1=按下 0=抬起
} xcd_key_t;

typedef struct {
    uint8_t  type;       // XCDMsgHello
    uint16_t screen_w;   // 物理点
    uint16_t screen_h;
    uint32_t max_fps;
} xcd_hello_t;

#pragma pack(pop)

#endif /* XCDProtocol_h */

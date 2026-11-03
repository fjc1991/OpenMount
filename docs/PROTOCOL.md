# Light Mount configuration protocol ("QLink" over USB HID)

This document describes how the be quiet! Light Mount keyboard is configured over USB, as
observed by talking to the keyboard. It was written for interoperability so the keyboard can be
used on macOS and Linux. It contains no vendor code.

Everything here was verified against a full-size Light Mount (USB `373F:0002`, firmware
revision `0x0035`, QLink version `0x17`). Anything marked *unverified* comes from the protocol
structure but has not been exercised on hardware yet.

## 1. Transport

The keyboard exposes three HID interfaces. Configuration uses the vendor interface:

| Usage page | Usage | Reports |
|---|---|---|
| `0xFF00` | `0x01` | 64-byte input, 64-byte output, 64-byte feature, no report ID |

Requests are sent as **output reports**. Replies and notifications arrive as **input reports**.
Never touch the boot-keyboard interface (page 1, usage 6). macOS doesn't need Input Monitoring
permission to open the vendor interface.

## 2. Frames

Each 64-byte report carries one frame:

| Offset | Size | Meaning |
|---|---|---|
| 0 | 1 | `L` = number of meaningful bytes that follow (`1…L`) |
| 1 | 1 | bits 0-6: frame sequence number (0 for the first frame of a message); bit 7: more frames follow |
| 2 | 1 | session id (0 until a session is open) |
| 3 … L | L-2 | message bytes |
| L+1 … 61 | | zero padding |
| 62 | 2 | CRC-16/MODBUS (poly `0xA001` reflected, init `0xFFFF`) over bytes 0…61, little-endian |

A frame holds up to 59 message bytes. Longer messages are split across frames with increasing
sequence numbers. Every frame except the last has bit 7 of byte 1 set.

## 3. Messages

```
[status/type] [request id] [feature id] [command id] [payload…]
```

* **Request:** byte 0 is `0`. The request id runs 1…255 and is echoed in the reply.
* **Reply:** byte 0 is the status (`0` = success).
* **Notification:** request id `0`, sent by the keyboard on its own (for example when another
  session changes settings).

All integers are **little-endian**.

### Status codes seen

| Code | Meaning (observed) |
|---|---|
| 0 | OK |
| 1 | invalid session |
| 3 | unknown command |
| 5 | invalid parameter / unknown id |
| 9 | session not active |
| 10 | not supported / invalid state on this firmware |
| 11 | invalid payload size |

## 4. Sessions (feature `0x01`, Root)

| Cmd | Name | Request | Reply |
|---|---|---|---|
| 1 | OpenSession | `u32 connection id, u8 client type` (0 unspecified, 1 desktop app, 2 web) | `u32 connection id, u8 session id, u8 active, u8 ?` |
| 2 | CloseSession | `u8 session id` | – |
| 3 | KeepAlive | – | – |
| 4 | GetSupportedFeatures | `u8 start index` | `u8 count, (u8 feature, u8 version)…` |
| 5 | GetQLinkVersion | – | `u32` |

OpenSession is the only command accepted with session id 0. Send the returned session id in
byte 2 of every later frame. Sessions expire if they stay idle, so send KeepAlive regularly.

The Light Mount reports these features: Root `01`, Firmware update `02`, Device info `03`,
Storage `04`, Polling rate `06`, Keyboard `07`, Lighting `10`, Bindings `11`, Macros `12`.

## 5. Device info (feature `0x03`)

| Cmd | Name | Reply |
|---|---|---|
| 1 | GetDeviceInfo | `u16 product id, u8 device type, u8 ?, u32 firmware` |
| 2 | GetSerialNumber | `u8 length, ASCII` |
| 5 | FactoryReset | request carries the serial number. *Not used by OpenMount.* |

Commands 3/4 (set/reset serial) and all of feature `0x02` (firmware update) are deliberately
**blocked** in OpenMount.

## 6. Lighting (feature `0x10`)

| Cmd | Name | Payload |
|---|---|---|
| 1 | GetLightingMode | → `u8 mode` |
| 2 | SetLightingMode | `u8 mode`: 0 disabled, 1 **global (on-board effect)**, 2 custom, 3 **realtime** |
| 6 | SetLayerConfig | `u8 layer (0 = global layer)` + layer config (below) |
| 13 | RealtimeUpdate | `u8 command count` + commands (below), only in mode 3 |

On firmware 0x35 these are answered with status 10: the layer layout, mask, name and global-layer
list commands (3, 4, 7, 8, 9, 10, 14) and calibration (15, 16). GetLayerConfig (5) always returns
a single `00`.

### Layer config

```
u8 effect      0 Static, 1 ColorWave, 2 Tornado, 3 Breathing, 4 Reactive, 5 Matrix, 6 Off, 7 Ripple
u8 direction   0 Up, 1 Down, 2 Left, 3 Right, 4 Clockwise, 5 Counterclockwise,
               6 Omnidirectional, 7 Horizontal, 8 Vertical, 9 Cross
u8 brightness  0-100 (%)
u8 speed       0-100 (%)
u8 color mode  then:
   0 single     RGB
   1 dual       RGB RGB
   2 gradient   u8 n, n × (RGB, u8 position)
   3 oriented   u8 type (0 linear, 1 radial, 2 conical), u16 angle, u8 n, n × (RGB, u8 position)
[optional]     3 extra bytes (purpose unverified)
```

Example, static orange at 100 %: `10 06 | 00 00 00 64 32 00 E6 30 00`.

### Realtime commands (mode 3)

| Id | Command | Body |
|---|---|---|
| 0 | Commit | – |
| 1 | Range, individual colours | `u16 first LED, u8 n, n × RGB` |
| 2 | Range, one colour | `u16 first LED, u8 n, RGB` |
| 3 | Single LED | `u16 LED, RGB` |

The payload must fit one message (keep each request under ~250 bytes). Changes show after a
Commit. Realtime colours stay after the session closes, but they're not stored in flash.

### LED indices

168 LEDs: 0-44 are the light bar along the top edge, then the dial (45) and the keys. See
`Sources/OpenMountKit/Models/KeyIndexTable.swift`.

## 7. Key bindings (feature `0x11`)

| Cmd | Name | Payload |
|---|---|---|
| 1 | GetBindings | `u16 offset` → `u16 count, (u16 key, binding)…` (only customised keys) |
| 2 | SetBinding | `u16 key, binding` |
| 3 | ClearBinding | `u16 key` (back to factory default) |
| 4 | GetConfig | → `u8 enabled` |
| 6 | GetBinding | `u16 key` → binding |

**Key id:** the key's binding index (see `KeyIndexTable.swift`). Add **132** for the Fn layer.

### Binding

```
u8 action, then:
 0 disabled
 1 key        u8 modifier mask (bit0 LCtrl, 1 LShift, 2 LAlt, 3 LGui, 4 RCtrl, 5 RShift, 6 RAlt, 7 RGui), u8 HID usage (page 7)
 2 media      u8 subtype: 1 Vol+, 2 Vol-, 3 Mute, 4 Mic mute, 5 Next, 6 Previous, 7 Play/Pause, 8 Stop
 3 mouse      u8 1 = button (u8 id: 0 L, 1 R, 2 M, 3 Fwd, 4 Back, u8 ?) | 2 = scroll (u8 dir: 0 up, 1 down, 2 left, 3 right)
 9 lighting   u8 subtype: 1 select effect (+ u8 effect), 2 next, 3 previous, 4 brightness+, 5 brightness-
10 macro      u16 macro id
```

## 8. Macros (feature `0x12`)

| Cmd | Name | Payload |
|---|---|---|
| 1 | GetMacros | `u16 offset` → `u16 count, u16 ids…` |
| 2 | SetMacros | `u16 count, u16 offset, u16 ids…` (defines which macros exist; count 0 deletes all) |
| 3 | GetMacroConfig | `u16 id` → `u8 playback, u8 delay mode, u16 delay` |
| 4 | SetMacroConfig | `u16 id, u8 playback (0 once, 1 while held, 2 repeat), u8 delay mode (0 recorded, 1 fixed, 2 random), u16 delay` |
| 5 | GetMacroEvents | `u16 id, u16 byte offset` → `u16 event count, raw event bytes from that offset` (one frame's worth; may end mid-event) |
| 6 | SetMacroEvents | `u16 id, u16 event count, u16 offset (0), events…` — **replaces the whole list**, so send every event in one multi-frame request |
| 7 | GetMacroName | `u16 id` → `u8 len, UTF-8` |
| 8 | SetMacroName | `u16 id, u8 len, UTF-8` |

Limits (from the vendor's device definition): 10 macros, 56 events each.

### Event

```
u8 type, body, u16 delay-after
 1 modifiers state  u8 mask
 2 key down         u8 HID usage
 3 key up           u8 HID usage
 6 consumer down    u16 usage      7 consumer up  u16 usage
10 mouse buttons    u8 mask
11 vertical scroll  i8             12 horizontal scroll i8
```

**Delay encoding (u16):** the top 2 bits select the unit (0 = 1 ms, 1 = 10 ms, 2 = 100 ms,
3 = 1 s) and the low 14 bits hold the count. Pick the smallest unit that fits.

## 9. Other features

* **Polling rate (`0x06`):** cmd 1 → `u16 Hz` (1000).
* **Keyboard (`0x07`):** cmd 1 → layout, cmd 2 → `u8 game-mode flags` (Win key, Alt+Tab,
  Alt+F4, Shift+Tab, Caps Lock lock-outs). *Writing is unverified.*
* **Storage (`0x04`):** 256 bytes of user data (cmd 1 info, 2 write, 3 read). OpenMount doesn't
  use it.

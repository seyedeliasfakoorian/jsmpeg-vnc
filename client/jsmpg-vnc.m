#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Set the body class to show/hide certain elements on mobile/desktop
NSString *className = ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) ? @"mobile" : @"desktop";
[[UIApplication sharedApplication].delegate window].rootViewController.view.className = className;

// Setup the WebSocket connection and start the player
NSURL *webSocketURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@/ws", (window.location.protocol == 'https:') ? @"wss" : @"ws", window.location.host]];
NSURLRequest *request = [NSURLRequest requestWithURL:webSocketURL];
NSURL *url = [[NSURL alloc] initWithString:[NSString stringWithFormat:@"%@://%@", (window.location.protocol == 'https:') ? @"https" : @"http", window.location.host]];
WebSocket *client = [[WebSocket alloc] initWithRequest:request url:url];

UIView *canvas = [self.view viewWithTag:1]; // Assuming you have a UIView with tag 1 as videoCanvas
Player *player = [[JSMPeg alloc] initWithClient:client canvas:canvas];

// Input

BOOL mouseLock = [document.location.href containsString:@"mouselock"];
CGPoint lastMouse = CGPointZero;
if (mouseLock) {
    // Request pointer lock if available
    if ([canvas respondsToSelector:@selector(requestPointerLock)]) {
        [canvas performSelector:@selector(requestPointerLock)];
    }
}

typedef NS_OPTIONS(NSUInteger, InputType) {
    InputTypeKey = 0x0001,
    InputTypeMouseButton = 0x0002,
    InputTypeMouseAbsolute = 0x0004,
    InputTypeMouseRelative = 0x0008,
};

typedef NS_OPTIONS(NSUInteger, InputState) {
    InputStateKeyDown = 0x01,
    InputStateKeyUp = 0x00,
    InputStateMouse1Down = 0x0002,
    InputStateMouse1Up = 0x0004,
    InputStateMouse2Down = 0x0008,
    InputStateMouse2Up = 0x0010,
};

// Struct input_key_t { uint16_t type, uint16_t state; uint16_t key_code; }
- (void)sendKey:(UIEvent *)event action:(InputState)action keyCode:(uint16_t)keyCode {
    [client send:[[NSData alloc] initWithBytes:&(InputTypeKey) length:sizeof(InputType)]];
    [client send:[[NSData alloc] initWithBytes:&action length:sizeof(InputState)]];
    [client send:[[NSData alloc] initWithBytes:&keyCode length:sizeof(uint16_t)]];
    [event preventDefault];
}

// Struct input_mouse_t { uint16_t type, uint16_t flags; float32_t x; float32_t y; }
NSMutableData *mouseDataBuffer = [[NSMutableData alloc] initWithLength:12];
uint16_t *mouseDataTypeFlags = (uint16_t *)[mouseDataBuffer mutableBytes];
float *mouseDataCoords = (float *)(mouseDataTypeFlags + 2);

- (void)sendMouse:(UIEvent *)event action:(InputState)action {
    uint16_t type = 0;
    float x = 0, y = 0;

    if (action) {
        type |= InputTypeMouseButton;

        // Attempt to lock pointer at mouse1 down
        if (mouseLock && action == InputStateMouse1Down) {
            [canvas requestPointerLock];
        }
    }

    // Only make relative mouse movements if no button is pressed
    if (!action && mouseLock) {
        type |= InputTypeMouseRelative;

        UITouch *touch = [event.allTouches anyObject];
        x = [touch locationInView:canvas].x - lastMouse.x;
        y = [touch locationInView:canvas].y - lastMouse.y;

        lastMouse = [touch locationInView:canvas];
    }

    // If we send absolute mouse coords, we can always do so, even for button presses.
    if (!mouseLock) {
        type |= InputTypeMouseAbsolute;

        CGRect rect = [canvas bounds];
        float scaleX = canvas.frame.size.width / rect.size.width;
        float scaleY = canvas.frame.size.height / rect.size.height;

        UITouch *touch = [event.allTouches anyObject];
        x = ([touch locationInView:canvas].x - rect.origin.x) * scaleX;
        y = ([touch locationInView:canvas].y - rect.origin.y) * scaleY;
    }

    mouseDataTypeFlags[0] = type;
    mouseDataTypeFlags[1] = (uint16_t)action;
    mouseDataCoords[0] = x;
    mouseDataCoords[1] = y;

    [client send:mouseDataBuffer];
    [event preventDefault];
}

// Keyboard
- (void)keyDown:(UIEvent *)event {
    [self sendKey:event action:InputStateKeyDown keyCode:event.keyCode];
}

- (void)keyUp:(UIEvent *)event {
    [self sendKey:event action:InputStateKeyUp keyCode:event.keyCode];
}

// Mouse
- (void)mouseMove:(UIEvent *)event {
    [self sendMouse:event action:InputStateMouse1Down];
}

- (void)mouseDown:(UIEvent *)event {
    [self sendMouse:event action:(event.button == 2) ? InputStateMouse2Down : InputStateMouse1Down];
}

- (void)mouseUp:(UIEvent *)event {
    [self sendMouse:event action:(event.button == 2) ? InputStateMouse2Up : InputStateMouse1Up];
}

// Touch
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    lastMouse = [[touches anyObject] locationInView:canvas];
    [self sendMouse:event action:InputStateMouse1Down];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self sendMouse:event action:InputStateMouse1Up];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self sendMouse:event action:InputStateMouse1Down];
}

// Touch buttons emulating keyboard keys
- (void)defineTouchButton:(UIView *)element keyCode:(uint16_t)keyCode {
    [element addTarget:self action:@selector(sendKey:action:keyCode:) forControlEvents:UIControlEventTouchDown];
    [element addTarget:self action:@selector(sendKey:action:keyCode:) forControlEvents:UIControlEventTouchUp];
}

NSArray *touchKeys = @[/* Array of your touch keys */];
for (UIView *touchKey in touchKeys) {
    [self defineTouchButton:touchKey keyCode:[touchKey.tag intValue]];
}

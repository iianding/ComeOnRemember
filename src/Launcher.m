#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <WebKit/WebKit.h>

@interface StudyApp : NSObject <NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandlerWithReply>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) WKWebView *webView;
@property(nonatomic, strong) NSURL *pageURL;
@property(nonatomic, strong) NSURL *dataURL;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *storage;
@property(nonatomic, strong) AVSpeechSynthesizer *speaker;
@property(nonatomic) BOOL flushing;
@end

@implementation StudyApp

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.pageURL = [NSBundle.mainBundle URLForResource:@"index" withExtension:@"html"];
    NSURL *bridgeURL = [NSBundle.mainBundle URLForResource:@"NativeBridge" withExtension:@"js"];
    NSString *bridge = bridgeURL ? [NSString stringWithContentsOfURL:bridgeURL encoding:NSUTF8StringEncoding error:nil] : nil;
    NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *folder = [support URLByAppendingPathComponent:@"ComeOnRemember" isDirectory:YES];
    self.dataURL = [folder URLByAppendingPathComponent:@"StudyData.json"];
    NSError *error = nil;
    if (!self.pageURL || !bridge ||
        ![NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:&error]) {
        [self showError:error.localizedDescription ?: @"找不到应用内的网页文件。"];
        [NSApp terminate:nil];
        return;
    }

    self.storage = [NSMutableDictionary dictionary];
    if ([NSFileManager.defaultManager fileExistsAtPath:self.dataURL.path]) {
        NSData *data = [NSData dataWithContentsOfURL:self.dataURL options:0 error:&error];
        id saved = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&error] : nil;
        BOOL valid = [saved isKindOfClass:NSDictionary.class];
        for (id key in valid ? saved : @{}) {
            valid = valid && [saved[key] isKindOfClass:NSString.class];
        }
        if (!valid) {
            [self showError:@"无法读取本地学习记录。原文件仍保留在「资源库 → Application Support → ComeOnRemember」。"];
            [NSApp terminate:nil];
            return;
        }
        self.storage = [saved mutableCopy];
    }

    NSData *initial = [NSJSONSerialization dataWithJSONObject:self.storage options:0 error:nil];
    NSString *snapshot = [[NSString alloc] initWithData:initial encoding:NSUTF8StringEncoding];
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    [config.userContentController addScriptMessageHandlerWithReply:self contentWorld:WKContentWorld.pageWorld name:@"studyApp"];
    NSString *source = [NSString stringWithFormat:@"(() => { const snapshot = %@;\n%@\n})();",
                        snapshot ?: @"{}", bridge];
    [config.userContentController addUserScript:[[WKUserScript alloc] initWithSource:source
        injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]];

    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1180, 800)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
          NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    self.window.releasedWhenClosed = NO;
    self.window.title = @"ComeOnRemember";
    self.window.contentMinSize = NSMakeSize(500, 460);
    self.webView = [[WKWebView alloc] initWithFrame:self.window.contentView.bounds configuration:config];
    self.webView.navigationDelegate = self;
    self.webView.UIDelegate = self;
    self.window.contentView = self.webView;
    self.speaker = [[AVSpeechSynthesizer alloc] init];
    [self installMenu];
    [self.webView loadFileURL:self.pageURL allowingReadAccessToURL:self.pageURL.URLByDeletingLastPathComponent];
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activate];
}

- (void)installMenu {
    NSMenu *bar = [[NSMenu alloc] init];
    NSMenuItem *appItem = [[NSMenuItem alloc] init];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"ComeOnRemember"];
    [appMenu addItemWithTitle:@"退出 ComeOnRemember" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;
    [bar addItem:appItem];

    NSMenuItem *editItem = [[NSMenuItem alloc] init];
    NSMenu *edit = [[NSMenu alloc] initWithTitle:@"编辑"];
    [edit addItemWithTitle:@"撤销" action:@selector(undo:) keyEquivalent:@"z"];
    [edit addItemWithTitle:@"剪切" action:@selector(cut:) keyEquivalent:@"x"];
    [edit addItemWithTitle:@"复制" action:@selector(copy:) keyEquivalent:@"c"];
    [edit addItemWithTitle:@"粘贴" action:@selector(paste:) keyEquivalent:@"v"];
    [edit addItemWithTitle:@"全选" action:@selector(selectAll:) keyEquivalent:@"a"];
    editItem.submenu = edit;
    [bar addItem:editItem];
    NSMenuItem *windowItem = [[NSMenuItem alloc] init];
    NSMenu *windows = [[NSMenu alloc] initWithTitle:@"窗口"];
    [windows addItemWithTitle:@"关闭窗口" action:@selector(performClose:) keyEquivalent:@"w"];
    windowItem.submenu = windows;
    [bar addItem:windowItem];
    NSApp.mainMenu = bar;
    NSApp.windowsMenu = windows;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    if (!self.webView || self.flushing) return NSTerminateNow;
    self.flushing = YES;
    [self.webView callAsyncJavaScript:@"return await window.crNative?.flush() ?? true;"
        arguments:@{} inFrame:nil inContentWorld:WKContentWorld.pageWorld
        completionHandler:^(id result, NSError *error) {
            BOOL saved = error == nil && [result isKindOfClass:NSNumber.class] && [result boolValue];
            self.flushing = NO;
            if (!saved) {
                [self.window makeKeyAndOrderFront:nil];
                [self showError:@"无法确认学习记录已写入本地。请导出备份后再退出。"];
            }
            [sender replyToApplicationShouldTerminate:saved];
        }];
    return NSTerminateLater;
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action
    decisionHandler:(void (^)(WKNavigationActionPolicy))decision {
    decision([action.request.URL.URLByStandardizingPath isEqual:self.pageURL.URLByStandardizingPath]
        ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}

- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message
    replyHandler:(void (^)(id, NSString *))reply {
    if (!message.frameInfo.isMainFrame ||
        ![message.frameInfo.request.URL.URLByStandardizingPath isEqual:self.pageURL.URLByStandardizingPath] ||
        ![message.body isKindOfClass:NSDictionary.class]) {
        reply(nil, @"无法处理此请求。");
        return;
    }
    NSDictionary *body = message.body;
    NSString *action = body[@"action"];
    if ([action isEqual:@"save"]) {
        [self saveValue:body[@"value"] forKey:body[@"key"] reply:reply];
    } else if ([action isEqual:@"speak"] && [body[@"text"] isKindOfClass:NSString.class]) {
        [self speak:body[@"text"] reply:reply];
    } else if ([action isEqual:@"stopSpeech"]) {
        [self.speaker stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
        reply(@YES, nil);
    } else if ([action isEqual:@"export"] && [body[@"data"] isKindOfClass:NSString.class] &&
               [body[@"name"] isKindOfClass:NSString.class]) {
        [self exportBackup:body[@"data"] name:body[@"name"] reply:reply];
    } else if ([action isEqual:@"import"]) {
        [self importBackup:reply];
    } else {
        reply(nil, @"无法处理此请求。");
    }
}

- (void)saveValue:(id)value forKey:(id)key reply:(void (^)(id, NSString *))reply {
    if (![key isKindOfClass:NSString.class] || ![key hasPrefix:@"come-on-remember-"] ||
        (value != NSNull.null && ![value isKindOfClass:NSString.class])) {
        reply(nil, @"无效的学习记录。");
        return;
    }
    NSMutableDictionary *next = [self.storage mutableCopy];
    if (value == NSNull.null) [next removeObjectForKey:key];
    else next[key] = value;
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:next options:0 error:&error];
    if (!data || ![data writeToURL:self.dataURL options:NSDataWritingAtomic error:&error]) {
        reply(nil, error.localizedDescription ?: @"无法保存学习记录。");
        return;
    }
    self.storage = next;
    reply(@YES, nil);
}

- (void)speak:(NSString *)text reply:(void (^)(id, NSString *))reply {
    AVSpeechSynthesisVoice *voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"en-GB"] ?:
        [AVSpeechSynthesisVoice voiceWithLanguage:@"en-US"];
    if (!voice) {
        reply(nil, @"请先在系统设置中下载英语语音。");
        return;
    }
    [self.speaker stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc] initWithString:text];
    utterance.voice = voice;
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate * .88;
    [self.speaker speakUtterance:utterance];
    reply(@YES, nil);
}

- (void)exportBackup:(NSString *)data name:(NSString *)name reply:(void (^)(id, NSString *))reply {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[UTTypeJSON];
    panel.nameFieldStringValue = name.lastPathComponent;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) {
            reply(@NO, nil);
            return;
        }
        NSError *error = nil;
        BOOL saved = [data writeToURL:panel.URL atomically:YES encoding:NSUTF8StringEncoding error:&error];
        reply(saved ? @YES : nil, saved ? nil : error.localizedDescription ?: @"无法导出备份。");
    }];
}

- (void)importBackup:(void (^)(id, NSString *))reply {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedContentTypes = @[UTTypeJSON];
    panel.allowsMultipleSelection = NO;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) {
            reply(NSNull.null, nil);
            return;
        }
        NSError *error = nil;
        NSString *data = [NSString stringWithContentsOfURL:panel.URL encoding:NSUTF8StringEncoding error:&error];
        reply(data, data ? nil : error.localizedDescription ?: @"无法读取备份。");
    }];
}

- (void)showError:(NSString *)message {
    [NSApp activate];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"ComeOnRemember";
    alert.informativeText = message;
    [alert runModal];
}

@end

int main(void) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        StudyApp *delegate = [[StudyApp alloc] init];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}

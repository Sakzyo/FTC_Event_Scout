#import <Cocoa/Cocoa.h>
#import <Security/Security.h>
#import <WebKit/WebKit.h>
#import "FTCSettingsWindowController.h"

static NSString *const FTCKeychainService = @"org.ftceventscout.credentials";
static NSString *const FTCUsernameAccount = @"first-api-username";
static NSString *const FTCTokenAccount = @"first-api-token";

typedef NS_ENUM(NSInteger, FTCBackendErrorCode) {
    FTCBackendErrorSetup = 1,
    FTCBackendErrorExited = 2,
    FTCBackendErrorTimedOut = 3,
    FTCBackendErrorPythonNotFound = 4,
    FTCBackendErrorPythonPackagesMissing = 5,
};

static NSString *FTCKeychainRead(NSString *account) {
    NSDictionary *query = @{
        (__bridge NSString *)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge NSString *)kSecAttrService: FTCKeychainService,
        (__bridge NSString *)kSecAttrAccount: account,
        (__bridge NSString *)kSecReturnData: @YES,
        (__bridge NSString *)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
    };
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess || result == NULL) {
        return @"";
    }
    NSData *data = CFBridgingRelease(result);
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

static BOOL FTCKeychainWrite(NSString *account, NSString *value, NSError **error) {
    NSDictionary *lookup = @{
        (__bridge NSString *)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge NSString *)kSecAttrService: FTCKeychainService,
        (__bridge NSString *)kSecAttrAccount: account,
    };
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    OSStatus status = SecItemUpdate(
        (__bridge CFDictionaryRef)lookup,
        (__bridge CFDictionaryRef)@{(__bridge NSString *)kSecValueData: data}
    );
    if (status == errSecItemNotFound) {
        NSMutableDictionary *insert = [lookup mutableCopy];
        insert[(__bridge NSString *)kSecValueData] = data;
        status = SecItemAdd((__bridge CFDictionaryRef)insert, NULL);
    }
    if (status == errSecSuccess) {
        return YES;
    }
    if (error != NULL) {
        NSString *message = CFBridgingRelease(SecCopyErrorMessageString(status, NULL));
        *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                     code:status
                                 userInfo:@{NSLocalizedDescriptionKey: message ?: @"Keychain error"}];
    }
    return NO;
}

typedef void (^FTCBackendCompletion)(NSURL *url, NSError *error);

@interface FTCBackendController : NSObject
@property(nonatomic, strong) NSTask *task;
@property(nonatomic, strong) NSPipe *stdoutPipe;
@property(nonatomic, strong) NSPipe *stderrPipe;
@property(nonatomic, strong) NSMutableString *stdoutBuffer;
@property(nonatomic, strong) NSMutableString *stderrBuffer;
@property(nonatomic, copy) FTCBackendCompletion completion;
@property(nonatomic) BOOL completed;
@property(nonatomic, strong) NSURL *incompletePythonURL;
@property(nonatomic, copy) NSArray<NSString *> *missingPythonPackages;
- (void)startWithCompletion:(FTCBackendCompletion)completion;
- (void)stop;
@end

@implementation FTCBackendController

- (NSURL *)backendResourceURL {
    NSURL *url = [[[NSBundle mainBundle] resourceURL] URLByAppendingPathComponent:@"Backend" isDirectory:YES];
    return [[NSFileManager defaultManager] fileExistsAtPath:url.path] ? url : nil;
}

- (NSURL *)applicationDataURL:(NSError **)error {
    NSURL *base = [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory
                                                         inDomain:NSUserDomainMask
                                                appropriateForURL:nil
                                                           create:YES
                                                            error:error];
    if (base == nil) {
        return nil;
    }
    NSURL *directory = [base URLByAppendingPathComponent:@"FTC Event Scout" isDirectory:YES];
    if (![[NSFileManager defaultManager] createDirectoryAtURL:directory
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:error]) {
        return nil;
    }
    return directory;
}

- (BOOL)isPythonExecutableName:(NSString *)name {
    if ([name isEqualToString:@"python3"]) return YES;
    if (![name hasPrefix:@"python3."] || [name isEqualToString:@"python3-config"]) return NO;
    NSString *suffix = [name substringFromIndex:@"python3.".length];
    NSCharacterSet *notDigitsOrPeriods = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789."] invertedSet];
    return suffix.length > 0 && [suffix rangeOfCharacterFromSet:notDigitsOrPeriods].location == NSNotFound;
}

- (NSArray<NSNumber *> *)pythonVersionAtURL:(NSURL *)url {
    NSTask *task = [[NSTask alloc] init];
    NSPipe *output = [NSPipe pipe];
    task.executableURL = url;
    task.arguments = @[@"--version"];
    task.standardOutput = output;
    task.standardError = output;
    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) return nil;
    [task waitUntilExit];
    if (task.terminationStatus != 0) return nil;

    NSData *data = [output.fileHandleForReading readDataToEndOfFile];
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    NSRegularExpression *expression = [NSRegularExpression
        regularExpressionWithPattern:@"Python\\s+(\\d+)\\.(\\d+)(?:\\.(\\d+))?"
        options:0 error:nil];
    NSTextCheckingResult *match = [expression firstMatchInString:text options:0
        range:NSMakeRange(0, text.length)];
    if (match == nil) return nil;

    NSMutableArray<NSNumber *> *components = [NSMutableArray arrayWithCapacity:3];
    for (NSInteger index = 1; index <= 3; index++) {
        NSRange range = [match rangeAtIndex:index];
        NSInteger value = range.location == NSNotFound ? 0 : [[text substringWithRange:range] integerValue];
        [components addObject:@(value)];
    }
    return components.firstObject.integerValue == 3 ? components : nil;
}

- (NSComparisonResult)comparePythonVersion:(NSArray<NSNumber *> *)left
                                        to:(NSArray<NSNumber *> *)right {
    for (NSUInteger index = 0; index < 3; index++) {
        NSComparisonResult result = [left[index] compare:right[index]];
        if (result != NSOrderedSame) return result;
    }
    return NSOrderedSame;
}

- (NSArray<NSString *> *)missingPackagesAtPythonURL:(NSURL *)url {
    NSArray<NSString *> *requiredPackages = @[@"numpy", @"requests"];
    NSString *script = @"import importlib\n"
        @"missing = []\n"
        @"for package in ('numpy', 'requests'):\n"
        @"    try:\n"
        @"        importlib.import_module(package)\n"
        @"    except Exception:\n"
        @"        missing.append(package)\n"
        @"print(','.join(missing))\n";
    NSTask *task = [[NSTask alloc] init];
    NSPipe *output = [NSPipe pipe];
    task.executableURL = url;
    task.arguments = @[@"-B", @"-c", script];
    task.standardOutput = output;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;
    NSMutableDictionary *environment = [NSProcessInfo.processInfo.environment mutableCopy];
    environment[@"PYTHONDONTWRITEBYTECODE"] = @"1";
    task.environment = environment;
    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) return requiredPackages;
    [task waitUntilExit];
    if (task.terminationStatus != 0) return requiredPackages;

    NSData *data = [output.fileHandleForReading readDataToEndOfFile];
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return text.length == 0 ? @[] : [text componentsSeparatedByString:@","];
}

- (NSURL *)pythonURL {
    self.incompletePythonURL = nil;
    self.missingPythonPackages = nil;
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSString *home = fileManager.homeDirectoryForCurrentUser.path;
    NSMutableOrderedSet<NSString *> *paths = [NSMutableOrderedSet orderedSetWithArray:@[
        @"/opt/homebrew/bin/python3",
        @"/usr/local/bin/python3",
        @"/opt/local/bin/python3",
        @"/usr/bin/python3",
        [home stringByAppendingPathComponent:@"miniconda3/bin/python3"],
        [home stringByAppendingPathComponent:@"anaconda3/bin/python3"],
        [home stringByAppendingPathComponent:@"miniforge3/bin/python3"],
        [home stringByAppendingPathComponent:@"mambaforge/bin/python3"],
    ]];

    NSMutableOrderedSet<NSString *> *executableDirectories = [NSMutableOrderedSet orderedSet];
    NSString *environmentPath = NSProcessInfo.processInfo.environment[@"PATH"] ?: @"";
    [executableDirectories addObjectsFromArray:[environmentPath componentsSeparatedByString:@":"]];
    [executableDirectories addObjectsFromArray:@[
        @"/opt/homebrew/bin", @"/usr/local/bin", @"/opt/local/bin",
        [home stringByAppendingPathComponent:@".local/bin"],
    ]];
    for (NSString *directoryPath in executableDirectories) {
        NSURL *directory = [NSURL fileURLWithPath:directoryPath isDirectory:YES];
        NSArray<NSURL *> *entries = [fileManager contentsOfDirectoryAtURL:directory
            includingPropertiesForKeys:nil options:0 error:nil];
        for (NSURL *entry in entries) {
            if ([self isPythonExecutableName:entry.lastPathComponent]) [paths addObject:entry.path];
        }
    }

    NSArray<NSString *> *installationRoots = @[
        @"/Library/Frameworks/Python.framework/Versions",
        [home stringByAppendingPathComponent:@"Library/Frameworks/Python.framework/Versions"],
        [home stringByAppendingPathComponent:@".pyenv/versions"],
        [home stringByAppendingPathComponent:@".asdf/installs/python"],
        [home stringByAppendingPathComponent:@".local/share/mise/installs/python"],
    ];
    for (NSString *rootPath in installationRoots) {
        NSArray<NSURL *> *versions = [fileManager
            contentsOfDirectoryAtURL:[NSURL fileURLWithPath:rootPath isDirectory:YES]
            includingPropertiesForKeys:nil options:0 error:nil];
        for (NSURL *version in versions) {
            [paths addObject:[[version URLByAppendingPathComponent:@"bin/python3"] path]];
        }
    }

    for (NSString *rootPath in @[@"/opt/homebrew/opt", @"/usr/local/opt"]) {
        NSArray<NSURL *> *packages = [fileManager
            contentsOfDirectoryAtURL:[NSURL fileURLWithPath:rootPath isDirectory:YES]
            includingPropertiesForKeys:nil options:0 error:nil];
        for (NSURL *package in packages) {
            NSString *name = package.lastPathComponent;
            if ([name isEqualToString:@"python"] || [name hasPrefix:@"python@"]) {
                [paths addObject:[[package URLByAppendingPathComponent:@"bin/python3"] path]];
            }
        }
    }

    NSArray<NSNumber *> *latestVersion = nil;
    NSMutableArray<NSDictionary *> *installed = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSString *path in paths) {
        NSString *canonical = path.stringByExpandingTildeInPath.stringByResolvingSymlinksInPath;
        if ([seen containsObject:canonical]) continue;
        [seen addObject:canonical];
        if (![fileManager isExecutableFileAtPath:canonical]) continue;
        NSURL *url = [NSURL fileURLWithPath:canonical];
        NSArray<NSNumber *> *version = [self pythonVersionAtURL:url];
        if (version == nil) continue;
        [installed addObject:@{@"url": url, @"version": version}];
        if (latestVersion == nil ||
            [self comparePythonVersion:version to:latestVersion] == NSOrderedDescending) {
            latestVersion = version;
        }
    }

    for (NSDictionary *runtime in installed) {
        NSArray<NSNumber *> *version = runtime[@"version"];
        if ([self comparePythonVersion:version to:latestVersion] != NSOrderedSame) continue;
        NSURL *url = runtime[@"url"];
        NSArray<NSString *> *missing = [self missingPackagesAtPythonURL:url];
        if (missing.count == 0) return url;
        if (self.incompletePythonURL == nil) {
            self.incompletePythonURL = url;
            self.missingPythonPackages = missing;
        }
    }
    return nil;
}

- (void)finishWithURL:(NSURL *)url error:(NSError *)error {
    __block FTCBackendCompletion completion = nil;
    @synchronized (self) {
        if (self.completed) {
            return;
        }
        self.completed = YES;
        completion = [self.completion copy];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion != nil) completion(url, error);
    });
}

- (void)startWithCompletion:(FTCBackendCompletion)completion {
    [self stop];
    self.completed = NO;
    self.completion = completion;
    self.stdoutBuffer = [NSMutableString string];
    self.stderrBuffer = [NSMutableString string];

    NSError *directoryError = nil;
    NSURL *resources = [self backendResourceURL];
    NSURL *dataDirectory = [self applicationDataURL:&directoryError];
    NSURL *python = [self pythonURL];
    if (python == nil) {
        if (self.incompletePythonURL != nil && self.missingPythonPackages.count > 0) {
            NSString *packages = [self.missingPythonPackages componentsJoinedByString:@" "];
            NSString *message = [NSString stringWithFormat:
                @"The newest Python 3 installation is missing %@. Install them with \"%@\" -m pip install %@, then try again.",
                [self.missingPythonPackages componentsJoinedByString:@", "],
                self.incompletePythonURL.path, packages];
            NSError *error = [NSError errorWithDomain:@"FTCEventScout"
                code:FTCBackendErrorPythonPackagesMissing
                userInfo:@{NSLocalizedDescriptionKey: message}];
            [self finishWithURL:nil error:error];
            return;
        }
        NSError *error = [NSError errorWithDomain:@"FTCEventScout"
            code:FTCBackendErrorPythonNotFound
            userInfo:@{NSLocalizedDescriptionKey:
                @"Python 3 was not found. Install the latest Python 3 for macOS, then try again."}];
        [self finishWithURL:nil error:error];
        return;
    }
    if (resources == nil || dataDirectory == nil) {
        NSString *message = resources == nil
            ? @"The app’s dashboard resources are missing."
            : directoryError.localizedDescription;
        NSError *error = [NSError errorWithDomain:@"FTCEventScout" code:FTCBackendErrorSetup
                                         userInfo:@{NSLocalizedDescriptionKey: message ?: @"Local server setup failed."}];
        [self finishWithURL:nil error:error];
        return;
    }

    NSURL *script = [resources URLByAppendingPathComponent:@"web_server.py"];
    NSTask *task = [[NSTask alloc] init];
    self.task = task;
    self.stdoutPipe = [NSPipe pipe];
    self.stderrPipe = [NSPipe pipe];
    task.executableURL = python;
    task.arguments = @[
        @"-B", script.path, @"0", @"--data-dir", dataDirectory.path,
        @"--resource-dir", resources.path,
    ];
    task.currentDirectoryURL = dataDirectory;
    task.standardOutput = self.stdoutPipe;
    task.standardError = self.stderrPipe;

    NSMutableDictionary *environment = [NSProcessInfo.processInfo.environment mutableCopy];
    environment[@"PYTHONUNBUFFERED"] = @"1";
    environment[@"PYTHONDONTWRITEBYTECODE"] = @"1";
    environment[@"FTC_SCOUT_APP"] = @"1";
    NSString *username = FTCKeychainRead(FTCUsernameAccount);
    NSString *token = FTCKeychainRead(FTCTokenAccount);
    if (username.length > 0) environment[@"USERNAME"] = username;
    else [environment removeObjectForKey:@"USERNAME"];
    if (token.length > 0) environment[@"TOKEN"] = token;
    else [environment removeObjectForKey:@"TOKEN"];
    task.environment = environment;

    __weak typeof(self) weakSelf = self;
    self.stdoutPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
        NSData *data = handle.availableData;
        if (data.length == 0) return;
        NSString *chunk = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
        typeof(self) self = weakSelf;
        if (self == nil || self.task != task) return;
        @synchronized (self.stdoutBuffer) {
            [self.stdoutBuffer appendString:chunk];
            NSRange newline;
            while ((newline = [self.stdoutBuffer rangeOfString:@"\n"]).location != NSNotFound) {
                NSString *line = [[self.stdoutBuffer substringToIndex:newline.location]
                    stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                [self.stdoutBuffer deleteCharactersInRange:NSMakeRange(0, NSMaxRange(newline))];
                if ([line hasPrefix:@"READY "]) {
                    NSURL *url = [NSURL URLWithString:[line substringFromIndex:6]];
                    if (url != nil) [self finishWithURL:url error:nil];
                }
            }
        }
    };
    self.stderrPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
        NSData *data = handle.availableData;
        if (data.length == 0) return;
        NSString *chunk = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
        typeof(self) self = weakSelf;
        if (self != nil && self.task == task) {
            @synchronized (self.stderrBuffer) { [self.stderrBuffer appendString:chunk]; }
        }
    };
    task.terminationHandler = ^(NSTask *finishedTask) {
        typeof(self) self = weakSelf;
        if (self == nil || self.task != finishedTask || self.completed) return;
        NSString *detail;
        @synchronized (self.stderrBuffer) { detail = [self.stderrBuffer copy]; }
        detail = [detail stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (detail.length == 0) {
            detail = [NSString stringWithFormat:@"The local server exited with status %d.", finishedTask.terminationStatus];
        }
        NSError *error = [NSError errorWithDomain:@"FTCEventScout" code:FTCBackendErrorExited
                                         userInfo:@{NSLocalizedDescriptionKey: detail}];
        [self finishWithURL:nil error:error];
    };

    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        [self finishWithURL:nil error:launchError];
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        typeof(self) self = weakSelf;
        if (self == nil || self.task != task || self.completed || !task.running) return;
        NSError *error = [NSError errorWithDomain:@"FTCEventScout" code:FTCBackendErrorTimedOut
                                         userInfo:@{NSLocalizedDescriptionKey: @"The local server did not become ready within 15 seconds."}];
        [self finishWithURL:nil error:error];
        [task terminate];
    });
}

- (void)stop {
    self.stdoutPipe.fileHandleForReading.readabilityHandler = nil;
    self.stderrPipe.fileHandleForReading.readabilityHandler = nil;
    if (self.task.running) {
        [self.task terminate];
    }
    self.task = nil;
    self.stdoutPipe = nil;
    self.stderrPipe = nil;
}

@end

static NSToolbarItemIdentifier const FTCToolbarEventSearch = @"org.ftceventscout.toolbar.event-search";
static NSToolbarItemIdentifier const FTCToolbarReload = @"org.ftceventscout.toolbar.reload";
static NSToolbarItemIdentifier const FTCToolbarSettings = @"org.ftceventscout.toolbar.settings";

@interface FTCAppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, NSToolbarDelegate,
    NSToolbarItemValidation, NSMenuItemValidation, WKNavigationDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) WKWebView *webView;
@property(nonatomic, strong) FTCBackendController *backend;
@property(nonatomic, strong) NSURL *dashboardURL;
@property(nonatomic, strong) NSSearchField *eventSearchField;
@property(nonatomic, strong) FTCSettingsWindowController *settingsWindowController;
@property(nonatomic, strong) NSTextField *credentialUsernameField;
@property(nonatomic, strong) NSSecureTextField *credentialTokenField;
@property(nonatomic, strong) NSTextField *credentialStatusLabel;
@end

@implementation FTCAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self buildMenus];
    self.backend = [[FTCBackendController alloc] init];
    NSRect frame = NSMakeRect(0, 0, 1180, 760);
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:NSWindowStyleMaskTitled |
                                                        NSWindowStyleMaskClosable |
                                                        NSWindowStyleMaskMiniaturizable |
                                                        NSWindowStyleMaskResizable
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.title = @"FTC Event Scout";
    self.window.minSize = NSMakeSize(820, 560);
    self.window.delegate = self;
    [self.window setFrameAutosaveName:@"FTCEventScoutMainWindow"];
    if (@available(macOS 11.0, *)) self.window.toolbarStyle = NSWindowToolbarStyleUnified;
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"FTCEventScoutToolbar"];
    toolbar.delegate = self;
    toolbar.displayMode = NSToolbarDisplayModeIconOnly;
    toolbar.allowsUserCustomization = NO;
    self.window.toolbar = toolbar;
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    if ([self hasCompleteCredentials]) {
        [self startBackend];
    } else {
        [self showCredentialSetup];
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }

- (void)applicationWillTerminate:(NSNotification *)notification { [self.backend stop]; }

- (void)buildMenus {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem *appRoot = [[NSMenuItem alloc] initWithTitle:@"FTC Event Scout" action:nil keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"FTC Event Scout"];
    [appMenu addItemWithTitle:@"About FTC Event Scout" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *settings = [appMenu addItemWithTitle:@"Settings…" action:@selector(showSettings:) keyEquivalent:@","];
    settings.target = self;
    [appMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *services = [[NSMenuItem alloc] initWithTitle:@"Services" action:nil keyEquivalent:@""];
    services.submenu = [[NSMenu alloc] initWithTitle:@"Services"];
    NSApp.servicesMenu = services.submenu;
    [appMenu addItem:services];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Hide FTC Event Scout" action:@selector(hide:) keyEquivalent:@"h"];
    NSMenuItem *hideOthers = [appMenu addItemWithTitle:@"Hide Others"
                                                action:@selector(hideOtherApplications:)
                                         keyEquivalent:@"h"];
    hideOthers.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [appMenu addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit FTC Event Scout" action:@selector(terminate:) keyEquivalent:@"q"];
    appRoot.submenu = appMenu;
    [mainMenu addItem:appRoot];

    NSMenuItem *editRoot = [[NSMenuItem alloc] initWithTitle:@"Edit" action:nil keyEquivalent:@""];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
    NSMenuItem *redo = [editMenu addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"z"];
    redo.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Delete" action:@selector(delete:) keyEquivalent:@""];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    editRoot.submenu = editMenu;
    [mainMenu addItem:editRoot];

    NSMenuItem *scoutRoot = [[NSMenuItem alloc] initWithTitle:@"Scout" action:nil keyEquivalent:@""];
    NSMenu *scoutMenu = [[NSMenu alloc] initWithTitle:@"Scout"];
    NSMenuItem *focus = [scoutMenu addItemWithTitle:@"Load Event…" action:@selector(focusEventCode:) keyEquivalent:@"l"];
    focus.target = self;
    NSMenuItem *reload = [scoutMenu addItemWithTitle:@"Reload Dashboard" action:@selector(reloadDashboard:) keyEquivalent:@"r"];
    reload.target = self;
    NSMenuItem *restart = [scoutMenu addItemWithTitle:@"Restart Local Server" action:@selector(startBackend) keyEquivalent:@"R"];
    restart.target = self;
    scoutRoot.submenu = scoutMenu;
    [mainMenu addItem:scoutRoot];

    NSMenuItem *windowRoot = [[NSMenuItem alloc] initWithTitle:@"Window" action:nil keyEquivalent:@""];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [windowMenu addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [windowMenu addItemWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];
    [windowMenu addItem:[NSMenuItem separatorItem]];
    [windowMenu addItemWithTitle:@"Bring All to Front" action:@selector(arrangeInFront:) keyEquivalent:@""];
    windowRoot.submenu = windowMenu;
    [mainMenu addItem:windowRoot];
    NSApp.windowsMenu = windowMenu;
    NSApp.mainMenu = mainMenu;
}

- (void)showCenteredTitle:(NSString *)title detail:(NSString *)detail retry:(BOOL)retry {
    [self setDashboardControlsEnabled:NO];
    NSView *container = [[NSView alloc] initWithFrame:self.window.contentView.bounds];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    NSTextField *titleLabel = [NSTextField labelWithString:title];
    titleLabel.font = [NSFont systemFontOfSize:20 weight:NSFontWeightSemibold];
    titleLabel.alignment = NSTextAlignmentCenter;
    NSTextField *detailLabel = [NSTextField wrappingLabelWithString:detail];
    detailLabel.textColor = NSColor.secondaryLabelColor;
    detailLabel.alignment = NSTextAlignmentCenter;
    detailLabel.maximumNumberOfLines = 0;
    NSStackView *stack = [NSStackView stackViewWithViews:@[titleLabel, detailLabel]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 8;
    stack.alignment = NSLayoutAttributeCenterX;
    if (retry) {
        NSButton *settings = [NSButton buttonWithTitle:@"Open Settings" target:self action:@selector(showSettings:)];
        NSButton *retryButton = [NSButton buttonWithTitle:@"Try Again" target:self action:@selector(startBackend)];
        retryButton.bezelStyle = NSBezelStyleRounded;
        NSStackView *actions = [NSStackView stackViewWithViews:@[settings, retryButton]];
        actions.spacing = 8;
        [stack addArrangedSubview:actions];
    } else {
        NSProgressIndicator *progress = [[NSProgressIndicator alloc] init];
        progress.style = NSProgressIndicatorStyleSpinning;
        progress.controlSize = NSControlSizeSmall;
        [progress startAnimation:nil];
        [stack addArrangedSubview:progress];
    }
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:stack];
    self.window.contentView = container;
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [stack.widthAnchor constraintLessThanOrEqualToConstant:560],
    ]];
}

- (NSString *)trimmedCredential:(NSString *)value {
    return [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

- (BOOL)hasCompleteCredentials {
    return [self trimmedCredential:FTCKeychainRead(FTCUsernameAccount)].length > 0 &&
        [self trimmedCredential:FTCKeychainRead(FTCTokenAccount)].length > 0;
}

- (void)setDashboardControlsEnabled:(BOOL)enabled {
    self.eventSearchField.enabled = enabled;
    [self.window.toolbar validateVisibleItems];
}

- (void)showCredentialSetup {
    [self.backend stop];
    self.dashboardURL = nil;
    self.webView = nil;
    [self setDashboardControlsEnabled:NO];

    NSView *container = [[NSView alloc] initWithFrame:self.window.contentView.bounds];
    container.translatesAutoresizingMaskIntoConstraints = NO;

    NSImageView *icon = [[NSImageView alloc] init];
    icon.image = [NSImage imageWithSystemSymbolName:@"person.badge.key"
                           accessibilityDescription:nil];
    icon.symbolConfiguration = [NSImageSymbolConfiguration
        configurationWithPointSize:44 weight:NSFontWeightRegular];
    icon.contentTintColor = NSColor.secondaryLabelColor;
    [icon setAccessibilityElement:NO];

    NSTextField *title = [NSTextField labelWithString:@"Connect to FIRST Events"];
    title.font = [NSFont systemFontOfSize:26 weight:NSFontWeightSemibold];
    title.alignment = NSTextAlignmentCenter;

    NSTextField *detail = [NSTextField wrappingLabelWithString:
        @"Enter your FIRST Events API credentials to start the scouting dashboard."];
    detail.textColor = NSColor.secondaryLabelColor;
    detail.alignment = NSTextAlignmentCenter;
    detail.maximumNumberOfLines = 0;

    NSTextField *username = [[NSTextField alloc] init];
    username.stringValue = FTCKeychainRead(FTCUsernameAccount);
    username.placeholderString = @"FIRST API username";
    username.accessibilityLabel = @"FIRST API username";
    self.credentialUsernameField = username;

    NSSecureTextField *token = [[NSSecureTextField alloc] init];
    token.stringValue = FTCKeychainRead(FTCTokenAccount);
    token.placeholderString = @"FIRST API token";
    token.accessibilityLabel = @"FIRST API token";
    self.credentialTokenField = token;

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[[NSTextField labelWithString:@"Username"], username],
        @[[NSTextField labelWithString:@"Token"], token],
    ]];
    grid.rowSpacing = 10;
    grid.columnSpacing = 12;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [grid columnAtIndex:1].width = 340;

    NSTextField *securityNote = [NSTextField wrappingLabelWithString:
        @"Your credentials are stored in your macOS login Keychain and passed only to the local server."];
    securityNote.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    securityNote.textColor = NSColor.secondaryLabelColor;
    securityNote.alignment = NSTextAlignmentCenter;
    securityNote.maximumNumberOfLines = 0;

    NSTextField *status = [NSTextField wrappingLabelWithString:@""];
    status.textColor = NSColor.systemRedColor;
    status.alignment = NSTextAlignmentCenter;
    status.maximumNumberOfLines = 0;
    status.hidden = YES;
    self.credentialStatusLabel = status;

    NSButton *save = [NSButton buttonWithTitle:@"Save and Continue"
                                         target:self
                                         action:@selector(saveStartupCredentials:)];
    save.bezelStyle = NSBezelStyleRounded;
    save.controlSize = NSControlSizeLarge;
    save.keyEquivalent = @"\r";

    NSStackView *stack = [NSStackView stackViewWithViews:@[
        icon, title, detail, grid, securityNote, status, save,
    ]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeCenterX;
    stack.spacing = 10;
    [stack setCustomSpacing:20 afterView:detail];
    [stack setCustomSpacing:16 afterView:grid];
    [stack setCustomSpacing:18 afterView:securityNote];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:stack];
    self.window.contentView = container;

    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [stack.widthAnchor constraintLessThanOrEqualToConstant:520],
        [detail.widthAnchor constraintEqualToConstant:480],
        [securityNote.widthAnchor constraintEqualToConstant:480],
        [status.widthAnchor constraintEqualToConstant:480],
    ]];
    [self.window makeFirstResponder:username.stringValue.length == 0 ? username : token];
}

- (void)saveStartupCredentials:(id)sender {
    NSString *username = [self trimmedCredential:self.credentialUsernameField.stringValue];
    NSString *token = [self trimmedCredential:self.credentialTokenField.stringValue];
    if (username.length == 0 || token.length == 0) {
        self.credentialStatusLabel.stringValue = @"Enter both your FIRST API username and token.";
        self.credentialStatusLabel.hidden = NO;
        [self.window makeFirstResponder:username.length == 0
            ? self.credentialUsernameField : self.credentialTokenField];
        return;
    }

    NSError *error = nil;
    if (!FTCKeychainWrite(FTCUsernameAccount, username, &error) ||
        !FTCKeychainWrite(FTCTokenAccount, token, &error)) {
        self.credentialStatusLabel.stringValue = [NSString stringWithFormat:
            @"Could not save credentials: %@", error.localizedDescription ?: @"Keychain error"];
        self.credentialStatusLabel.hidden = NO;
        return;
    }
    [self startBackend];
}

- (void)showPythonRequired {
    self.dashboardURL = nil;
    self.webView = nil;
    [self setDashboardControlsEnabled:NO];
    NSView *container = [[NSView alloc] initWithFrame:self.window.contentView.bounds];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    NSTextField *title = [NSTextField labelWithString:@"Python 3 Required"];
    title.font = [NSFont systemFontOfSize:20 weight:NSFontWeightSemibold];
    title.alignment = NSTextAlignmentCenter;
    NSTextField *detail = [NSTextField wrappingLabelWithString:
        @"Install the latest Python 3 for macOS. FTC Event Scout will find and use it automatically—there is no runtime setting to configure."];
    detail.textColor = NSColor.secondaryLabelColor;
    detail.alignment = NSTextAlignmentCenter;
    detail.maximumNumberOfLines = 0;
    NSButton *download = [NSButton buttonWithTitle:@"Download Python 3"
                                             target:self action:@selector(openPythonDownload:)];
    NSButton *retry = [NSButton buttonWithTitle:@"Try Again"
                                          target:self action:@selector(startBackend)];
    retry.keyEquivalent = @"\r";
    NSStackView *actions = [NSStackView stackViewWithViews:@[download, retry]];
    actions.spacing = 8;
    NSStackView *stack = [NSStackView stackViewWithViews:@[title, detail, actions]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeCenterX;
    stack.spacing = 10;
    [stack setCustomSpacing:18 afterView:detail];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:stack];
    self.window.contentView = container;
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [detail.widthAnchor constraintEqualToConstant:560],
    ]];
}

- (void)showPythonPackagesRequired:(NSString *)message {
    self.dashboardURL = nil;
    self.webView = nil;
    [self setDashboardControlsEnabled:NO];
    NSView *container = [[NSView alloc] initWithFrame:self.window.contentView.bounds];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    NSTextField *title = [NSTextField labelWithString:@"Python Packages Required"];
    title.font = [NSFont systemFontOfSize:20 weight:NSFontWeightSemibold];
    title.alignment = NSTextAlignmentCenter;
    NSTextField *detail = [NSTextField wrappingLabelWithString:message];
    detail.textColor = NSColor.secondaryLabelColor;
    detail.alignment = NSTextAlignmentCenter;
    detail.maximumNumberOfLines = 0;
    detail.selectable = YES;
    NSButton *retry = [NSButton buttonWithTitle:@"Try Again"
                                          target:self action:@selector(startBackend)];
    retry.keyEquivalent = @"\r";
    NSStackView *stack = [NSStackView stackViewWithViews:@[title, detail, retry]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeCenterX;
    stack.spacing = 10;
    [stack setCustomSpacing:18 afterView:detail];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:stack];
    self.window.contentView = container;
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [detail.widthAnchor constraintEqualToConstant:600],
    ]];
}

- (void)openPythonDownload:(id)sender {
    NSURL *url = [NSURL URLWithString:@"https://www.python.org/downloads/macos/"];
    if (url != nil) [NSWorkspace.sharedWorkspace openURL:url];
}

- (NSURL *)nativeDashboardURLFromURL:(NSURL *)url {
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if (components == nil) return url;
    NSMutableArray<NSURLQueryItem *> *items = [components.queryItems mutableCopy] ?: [NSMutableArray array];
    [items addObject:[NSURLQueryItem queryItemWithName:@"native" value:@"1"]];
    components.queryItems = items;
    return components.URL ?: url;
}

- (void)startBackend {
    if (![self hasCompleteCredentials]) {
        [self showCredentialSetup];
        return;
    }
    self.dashboardURL = nil;
    self.webView = nil;
    [self showCenteredTitle:@"Starting FTC Event Scout"
                     detail:@"Preparing the local scouting server and dashboard…"
                      retry:NO];
    __weak typeof(self) weakSelf = self;
    [self.backend startWithCompletion:^(NSURL *url, NSError *error) {
        typeof(self) self = weakSelf;
        if (self == nil) return;
        if (error != nil) {
            if ([error.domain isEqualToString:@"FTCEventScout"] &&
                error.code == FTCBackendErrorPythonNotFound) {
                [self showPythonRequired];
                return;
            }
            if ([error.domain isEqualToString:@"FTCEventScout"] &&
                error.code == FTCBackendErrorPythonPackagesMissing) {
                [self showPythonPackagesRequired:error.localizedDescription];
                return;
            }
            [self showCenteredTitle:@"Local Server Unavailable" detail:error.localizedDescription retry:YES];
            return;
        }
        self.dashboardURL = url;
        WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
        WKWebView *webView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
        self.webView = webView;
        [self setDashboardControlsEnabled:YES];
        webView.navigationDelegate = self;
        webView.allowsMagnification = YES;
        if (@available(macOS 12.0, *)) webView.underPageBackgroundColor = NSColor.windowBackgroundColor;
        webView.translatesAutoresizingMaskIntoConstraints = NO;
        NSView *container = [[NSView alloc] initWithFrame:self.window.contentView.bounds];
        [container addSubview:webView];
        self.window.contentView = container;
        [NSLayoutConstraint activateConstraints:@[
            [webView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [webView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [webView.topAnchor constraintEqualToAnchor:container.topAnchor],
            [webView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        ]];
        [webView loadRequest:[NSURLRequest requestWithURL:[self nativeDashboardURLFromURL:url]
                                              cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                          timeoutInterval:30]];
    }];
}

- (void)focusEventCode:(id)sender {
    if (self.eventSearchField.enabled) {
        [self.window makeFirstResponder:self.eventSearchField];
    }
}

- (void)reloadDashboard:(id)sender { [self.webView reload]; }

- (void)submitEventCode:(id)sender {
    NSString *eventCode = [[self trimmedCredential:self.eventSearchField.stringValue] uppercaseString];
    if (eventCode.length == 0 || self.webView == nil) {
        NSBeep();
        [self.window makeFirstResponder:self.eventSearchField];
        return;
    }
    self.eventSearchField.stringValue = eventCode;

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:@[eventCode] options:0 error:nil];
    NSString *json = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    if (json == nil) return;
    NSString *script = [NSString stringWithFormat:
        @"(() => { const code = (%@)[0]; const input = document.getElementById('event-code'); "
         "if (!input) return; input.value = code; input.dispatchEvent(new Event('input', { bubbles: true })); "
         "const form = document.getElementById('event-form'); if (form?.requestSubmit) form.requestSubmit(); "
         "else document.getElementById('load-event-button')?.click(); })();",
        json];
    [self.webView evaluateJavaScript:script completionHandler:nil];
}

- (void)showSettings:(id)sender {
    NSString *username = FTCKeychainRead(FTCUsernameAccount);
    NSString *token = FTCKeychainRead(FTCTokenAccount);
    if (self.settingsWindowController == nil) {
        __weak typeof(self) weakSelf = self;
        self.settingsWindowController = [[FTCSettingsWindowController alloc]
            initWithUsername:username
                       token:token
                 saveHandler:^BOOL(NSString *updatedUsername, NSString *updatedToken, NSError **error) {
            typeof(self) self = weakSelf;
            if (self == nil) return NO;
            BOOL saved = FTCKeychainWrite(FTCUsernameAccount, updatedUsername, error) &&
                FTCKeychainWrite(FTCTokenAccount, updatedToken, error);
            if (saved) [self startBackend];
            return saved;
        }];
        NSWindow *settingsWindow = self.settingsWindowController.window;
        NSRect parent = self.window.frame;
        NSRect frame = settingsWindow.frame;
        frame.origin = NSMakePoint(NSMidX(parent) - NSWidth(frame) / 2,
                                   NSMidY(parent) - NSHeight(frame) / 2);
        [settingsWindow setFrame:frame display:NO];
    } else {
        [self.settingsWindowController updateUsername:username token:token];
    }
    [self.settingsWindowController showWindow:nil];
    [self.settingsWindowController.window makeKeyAndOrderFront:nil];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return @[NSToolbarFlexibleSpaceItemIdentifier, FTCToolbarEventSearch, FTCToolbarReload, FTCToolbarSettings];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return @[NSToolbarFlexibleSpaceItemIdentifier, FTCToolbarEventSearch, FTCToolbarReload, FTCToolbarSettings];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
       itemForItemIdentifier:(NSToolbarItemIdentifier)identifier
   willBeInsertedIntoToolbar:(BOOL)flag {
    if ([identifier isEqualToString:FTCToolbarEventSearch]) {
        NSSearchToolbarItem *searchItem = [[NSSearchToolbarItem alloc] initWithItemIdentifier:identifier];
        searchItem.label = @"Event Code";
        searchItem.toolTip = @"Enter an event code and press Return (⌘L)";
        searchItem.preferredWidthForSearchField = 220;
        searchItem.resignsFirstResponderWithCancel = YES;
        NSSearchField *searchField = searchItem.searchField;
        searchField.placeholderString = @"Event code";
        searchField.accessibilityLabel = @"FTC event code";
        searchField.recentsAutosaveName = @"FTCEventScoutRecentEventCodes";
        searchField.maximumRecents = 10;
        searchField.target = self;
        searchField.action = @selector(submitEventCode:);
        searchField.enabled = self.webView != nil;
        self.eventSearchField = searchField;
        return searchItem;
    }

    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    item.target = self;
    if ([identifier isEqualToString:FTCToolbarReload]) {
        item.label = @"Reload";
        item.toolTip = @"Reload Dashboard (⌘R)";
        item.image = [NSImage imageWithSystemSymbolName:@"arrow.clockwise" accessibilityDescription:@"Reload"];
        item.action = @selector(reloadDashboard:);
    } else {
        item.label = @"Settings";
        item.toolTip = @"Settings (⌘,)";
        item.image = [NSImage imageWithSystemSymbolName:@"gearshape" accessibilityDescription:@"Settings"];
        item.action = @selector(showSettings:);
    }
    return item;
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)item {
    if ([item.itemIdentifier isEqualToString:FTCToolbarReload]) return self.webView != nil;
    return YES;
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.action == @selector(focusEventCode:) || item.action == @selector(reloadDashboard:)) {
        return self.webView != nil;
    }
    return YES;
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [webView evaluateJavaScript:
        @"document.documentElement.classList.add('native-shell'); "
         "document.getElementById('event-code')?.value || '';"
        completionHandler:^(id result, NSError *error) {
        if ([result isKindOfClass:NSString.class] && [result length] > 0) {
            self.eventSearchField.stringValue = result;
        }
    }];
}

- (void)webView:(WKWebView *)webView
decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
 decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *destination = navigationAction.request.URL;
    if (navigationAction.navigationType == WKNavigationTypeLinkActivated &&
        destination != nil && ![destination.host isEqualToString:self.dashboardURL.host]) {
        [[NSWorkspace sharedWorkspace] openURL:destination];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        FTCAppDelegate *delegate = [[FTCAppDelegate alloc] init];
        application.delegate = delegate;
        [application setActivationPolicy:NSApplicationActivationPolicyRegular];
        [application run];
    }
    return 0;
}

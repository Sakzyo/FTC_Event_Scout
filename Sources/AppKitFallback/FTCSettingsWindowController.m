#import "FTCSettingsWindowController.h"

@interface FTCSettingsWindowController ()
@property(nonatomic, strong) NSTextField *usernameField;
@property(nonatomic, strong) NSSecureTextField *tokenField;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, copy) FTCSettingsSaveHandler saveHandler;
@end

@implementation FTCSettingsWindowController

- (instancetype)initWithUsername:(NSString *)username
                            token:(NSString *)token
                      saveHandler:(FTCSettingsSaveHandler)saveHandler {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 540, 260)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    self = [super initWithWindow:window];
    if (self == nil) return nil;

    self.saveHandler = saveHandler;
    window.title = @"Settings";
    window.releasedWhenClosed = NO;
    window.tabbingMode = NSWindowTabbingModeDisallowed;
    window.animationBehavior = NSWindowAnimationBehaviorUtilityWindow;
    window.contentView = [self contentView];
    [self updateUsername:username token:token];
    return self;
}

- (NSView *)contentView {
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 540, 260)];

    NSImageView *icon = [[NSImageView alloc] init];
    icon.image = [NSImage imageWithSystemSymbolName:@"person.badge.key"
                           accessibilityDescription:nil];
    icon.symbolConfiguration = [NSImageSymbolConfiguration
        configurationWithPointSize:30 weight:NSFontWeightRegular];
    icon.contentTintColor = NSColor.secondaryLabelColor;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [icon setAccessibilityElement:NO];

    NSTextField *title = [NSTextField labelWithString:@"FIRST Events API"];
    title.font = [NSFont systemFontOfSize:17 weight:NSFontWeightSemibold];

    NSTextField *detail = [NSTextField wrappingLabelWithString:
        @"Update the credentials used when FTC Event Scout connects to the official FIRST API."];
    detail.textColor = NSColor.secondaryLabelColor;
    detail.maximumNumberOfLines = 0;

    NSStackView *heading = [NSStackView stackViewWithViews:@[title, detail]];
    heading.orientation = NSUserInterfaceLayoutOrientationVertical;
    heading.alignment = NSLayoutAttributeLeading;
    heading.spacing = 3;

    NSStackView *header = [NSStackView stackViewWithViews:@[icon, heading]];
    header.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    header.alignment = NSLayoutAttributeTop;
    header.spacing = 12;

    self.usernameField = [[NSTextField alloc] init];
    self.usernameField.placeholderString = @"FIRST API username";
    self.usernameField.accessibilityLabel = @"FIRST API username";

    self.tokenField = [[NSSecureTextField alloc] init];
    self.tokenField.placeholderString = @"FIRST API token";
    self.tokenField.accessibilityLabel = @"FIRST API token";

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[[NSTextField labelWithString:@"Username"], self.usernameField],
        @[[NSTextField labelWithString:@"Token"], self.tokenField],
    ]];
    grid.rowSpacing = 10;
    grid.columnSpacing = 12;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [grid columnAtIndex:1].width = 340;

    NSTextField *securityNote = [NSTextField wrappingLabelWithString:
        @"Credentials are stored in your macOS login Keychain and passed only to the local server."];
    securityNote.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    securityNote.textColor = NSColor.secondaryLabelColor;
    securityNote.maximumNumberOfLines = 0;

    self.statusLabel = [NSTextField wrappingLabelWithString:@""];
    self.statusLabel.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    self.statusLabel.textColor = NSColor.systemRedColor;
    self.statusLabel.maximumNumberOfLines = 0;
    self.statusLabel.hidden = YES;

    NSButton *cancel = [NSButton buttonWithTitle:@"Cancel"
                                          target:self
                                          action:@selector(cancel:)];
    cancel.keyEquivalent = @"\e";
    NSButton *save = [NSButton buttonWithTitle:@"Save and Restart"
                                        target:self
                                        action:@selector(save:)];
    save.bezelStyle = NSBezelStyleRounded;
    save.keyEquivalent = @"\r";

    NSStackView *buttons = [NSStackView stackViewWithViews:@[cancel, save]];
    buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttons.spacing = 8;

    NSStackView *actions = [NSStackView stackViewWithViews:@[
        self.statusLabel, [NSView new], buttons,
    ]];
    actions.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    actions.alignment = NSLayoutAttributeCenterY;
    actions.spacing = 8;

    NSStackView *content = [NSStackView stackViewWithViews:@[
        header, grid, securityNote, actions,
    ]];
    content.orientation = NSUserInterfaceLayoutOrientationVertical;
    content.alignment = NSLayoutAttributeLeading;
    content.spacing = 14;
    [content setCustomSpacing:20 afterView:header];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:content];

    [NSLayoutConstraint activateConstraints:@[
        [icon.widthAnchor constraintEqualToConstant:36],
        [icon.heightAnchor constraintEqualToConstant:36],
        [header.widthAnchor constraintEqualToAnchor:content.widthAnchor],
        [detail.widthAnchor constraintEqualToConstant:400],
        [grid.widthAnchor constraintEqualToAnchor:content.widthAnchor],
        [securityNote.widthAnchor constraintEqualToAnchor:content.widthAnchor],
        [actions.widthAnchor constraintEqualToAnchor:content.widthAnchor],
        [self.statusLabel.widthAnchor constraintLessThanOrEqualToConstant:250],
        [content.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:28],
        [content.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-28],
        [content.topAnchor constraintEqualToAnchor:container.topAnchor constant:24],
        [content.bottomAnchor constraintLessThanOrEqualToAnchor:container.bottomAnchor constant:-20],
    ]];

    return container;
}

- (void)updateUsername:(NSString *)username token:(NSString *)token {
    self.usernameField.stringValue = username;
    self.tokenField.stringValue = token;
    self.statusLabel.stringValue = @"";
    self.statusLabel.hidden = YES;
}

- (NSString *)trimmedValue:(NSString *)value {
    return [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

- (void)save:(id)sender {
    NSString *username = [self trimmedValue:self.usernameField.stringValue];
    NSString *token = [self trimmedValue:self.tokenField.stringValue];
    if (username.length == 0 || token.length == 0) {
        self.statusLabel.stringValue = @"Enter both a username and token.";
        self.statusLabel.hidden = NO;
        [self.window makeFirstResponder:username.length == 0 ? self.usernameField : self.tokenField];
        return;
    }

    NSError *error = nil;
    if (self.saveHandler != nil && !self.saveHandler(username, token, &error)) {
        self.statusLabel.stringValue = error.localizedDescription ?: @"Could not save credentials.";
        self.statusLabel.hidden = NO;
        return;
    }

    [self.window performClose:nil];
}

- (void)cancel:(id)sender {
    [self.window performClose:nil];
}

@end

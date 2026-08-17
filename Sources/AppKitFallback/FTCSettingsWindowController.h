#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef BOOL (^FTCSettingsSaveHandler)(NSString *username, NSString *token, NSError **error);

@interface FTCSettingsWindowController : NSWindowController

- (instancetype)initWithUsername:(NSString *)username
                            token:(NSString *)token
                      saveHandler:(FTCSettingsSaveHandler)saveHandler;

- (void)updateUsername:(NSString *)username token:(NSString *)token;

@end

NS_ASSUME_NONNULL_END

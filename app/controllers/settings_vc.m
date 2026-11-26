#import "app_common.h"
#import "ui_theme.h"
#import "shiro_menus.h"
#import "shiro_dialog.h"
#include <unistd.h>
#include <math.h>
#include <CoreFoundation/CoreFoundation.h>

@interface ShiroSettingsController () {
    NSDictionary *_settings;
    CGFloat _groupedInsetX;
}
@end
@implementation ShiroSettingsController
- (id)init {
    return [super initWithControl:[[[ShiroControl alloc] initWithSocketPath:SHIRO_SOCK] autorelease]];
}
- (void)dealloc { [_settings release]; [super dealloc]; }
- (NSString *)devTitle { return ShiroLocalizedText(@"Settings"); }
- (const char *)devScreenName { return "settings"; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)] autorelease];
}
- (void)done { ShiroDismissModal(self, nil); }
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated]; [_tv reloadData];
    [_ctl request:[NSDictionary dictionaryWithObject:@"status" forKey:@"command"] reply:^(NSDictionary *response, NSString *error) {
        [_settings release]; _settings = error ? nil : [response copy]; [_tv reloadData];
    }];
}
- (NSArray *)rows:(NSInteger)section {
    if (section == 0) return [NSArray arrayWithObjects:@"Connect at startup", @"Reconnect automatically", @"Try another server", @"Reconnect attempts", nil];
    if (section == 1) return [NSArray arrayWithObjects:@"Theme", @"Appearance", @"Falling foxes", @"Language", @"System Logs", @"Backup", nil];
    if (section == 2) return [NSArray arrayWithObjects:@"DNS", @"Registration proxy", @"About", nil];
    return [NSArray arrayWithObject:@"Developer settings"];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return ShiroDevMenuEnabled() ? 4 : 3; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return [self rows:section].count; }
- (NSString *)devHeaderForSection:(NSInteger)section {
    return ShiroLocalizedText([[NSArray arrayWithObjects:@"Main", @"App", @"Advanced", @"Developer settings", nil] objectAtIndex:section]);
}
- (NSString *)devFooterForSection:(NSInteger)section {
    if (section == 2) return ShiroLocalizedText(@"The proxy is used only for WARP registration. Optional login: scheme://user:password@host:port.");
    return section == 0 && !_settings ? ShiroLocalizedText(@"The daemon is not answering, so these cannot be read or changed.") : nil;
}
- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)index { return 54; }
- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)section { return 38; }
- (void)hideDeveloper { if (!ShiroDevMenuTapsLeft()) { ShiroSetDevMenuEnabled(NO); [_tv reloadData]; } }
- (UIView *)sectionTextViewWithText:(NSString *)text
                               font:(UIFont *)font
                             height:(CGFloat)height
                              width:(CGFloat)width {
    if (![text length]) return nil;
    UIView *wrap = [[[UIView alloc] initWithFrame:
                     CGRectMake(0, 0, width, height)] autorelease];
    wrap.backgroundColor = [UIColor clearColor];
    wrap.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    CGFloat inset = 16.0f + _groupedInsetX;
    UILabel *label = [[[UILabel alloc] initWithFrame:
                       CGRectMake(inset, 4.0f, width - inset * 2.0f, height - 6.0f)] autorelease];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                             UIViewAutoresizingFlexibleHeight;
    label.backgroundColor = [UIColor clearColor];
    label.font = font;
    label.numberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.text = text;
    label.textAlignment = NSTextAlignmentLeft;
    ShiroStyleMutedLabel(label);
    label.shadowColor = nil;
    label.shadowOffset = CGSizeZero;
    [wrap addSubview:label];
    return wrap;
}
- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)s {
    UIView *header = [self sectionTextViewWithText:[self devHeaderForSection:s]
                                              font:ShiroFontBody(15.0f, YES)
                                            height:38.0f
                                             width:tv.bounds.size.width];
    for (UIView *child in header.subviews)
        if ([child isKindOfClass:[UILabel class]])
            ((UILabel *)child).textAlignment = NSTextAlignmentCenter;
/* the same five taps that opened the section close it, so a tester who turned
   it on by accident is not stuck with it */
    if (header && s == 3) {
        header.userInteractionEnabled = YES;
        [header addGestureRecognizer:
            [[[UITapGestureRecognizer alloc] initWithTarget:self
                                                     action:@selector(hideDeveloper)] autorelease]];
    }
    return header;
}
- (UIView *)tableView:(UITableView *)tv viewForFooterInSection:(NSInteger)s {
    UIView *footer = [self sectionTextViewWithText:[self devFooterForSection:s]
                                              font:ShiroFontBody(12.0, NO)
                                            height:[self tableView:tv heightForFooterInSection:s]
                                             width:tv.bounds.size.width];
    return footer ? footer : [[[UIView alloc] initWithFrame:CGRectZero] autorelease];
}
- (CGFloat)tableView:(UITableView *)tv heightForFooterInSection:(NSInteger)s {
    NSString *text = [self devFooterForSection:s];
    if (![text length]) return 10.0f;
    CGFloat width = tv.bounds.size.width - 40.0f;
    if (width < 120.0f) width = 120.0f;
    CGSize size = ShiroTextSize(text, ShiroFontBody(12.0, NO), width);
    return MAX(36.0f, size.height + 16.0f);
}

/* a plain label in an owned view is the only way these keep the theme ink:
   from ios 14 UITableViewHeaderFooterView re-applies its own content
   configuration after willDisplayHeaderView:, which put the section titles
   back to the system colour (black on the dark palettes) */
- (void)tableView:(UITableView *)tv willDisplayCell:(UITableViewCell *)cell
 forRowAtIndexPath:(NSIndexPath *)ip {
    ShiroStyleGroupCell(cell, ip, [self tableView:tv numberOfRowsInSection:ip.section]);
/* uikit has already narrowed and centered cell.frame by the time this runs,
   so this is the real margin rather than a guess at one */
    CGFloat insetX = cell.frame.origin.x;
    if (insetX >= 0.0f && insetX < tv.bounds.size.width * 0.5f &&
        fabsf((float)(insetX - _groupedInsetX)) > 0.5f) {
        _groupedInsetX = insetX;
/* section 0's header is built before any row exists to measure against, so
   the first display leaves it at the wrong offset; once a row answers, redraw
   the headers that were built too early instead of leaving them stuck there */
        dispatch_async(dispatch_get_main_queue(), ^{
            [tv reloadData];
        });
    }
}
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"settings"];
    if (!cell) cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"settings"] autorelease];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.clipsToBounds = YES; cell.selectedBackgroundView = nil;
    cell.accessoryView = nil; cell.detailTextLabel.text = nil;
    cell.textLabel.textColor = kInk; cell.detailTextLabel.textColor = kInkMuted;
    cell.textLabel.backgroundColor = [UIColor clearColor]; cell.detailTextLabel.backgroundColor = [UIColor clearColor];
    cell.textLabel.font = ShiroFontBody(16, NO); cell.detailTextLabel.font = ShiroFontBody(15, NO);
    ShiroStyleGroupCell(cell, index, [self rows:index.section].count);
    NSString *name = [[self rows:index.section] objectAtIndex:index.row];
    NSDictionary *glyphs = [NSDictionary dictionaryWithObjectsAndKeys:@"rocket", @"Connect at startup", @"reconnect", @"Reconnect automatically", @"shuffle", @"Try another server", @"repeat", @"Reconnect attempts", @"palette", @"Theme", @"bolt", @"Appearance", @"shuffle", @"Falling foxes", @"globe", @"Language", @"logs", @"System Logs", @"backup", @"Backup", @"shield", @"DNS", @"globe", @"Registration proxy", @"info", @"About", @"code", @"Developer settings", nil];
    cell.textLabel.text = ShiroLocalizedText(name);
    cell.textLabel.font = ShiroFontBody(16, NO);
    cell.imageView.image = TintedIconNamed([NSString stringWithFormat:@"glyph-%@.png", [glyphs objectForKey:name]], 22, kInk);
    ShiroStyleSelectableCell(cell);
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    if ([name isEqualToString:@"Falling foxes"]) {
        UISwitch *sw = [[[UISwitch alloc] init] autorelease];
        id stored = [[NSUserDefaults standardUserDefaults] objectForKey:@"ShiroFallingFoxes"];
        sw.on = !stored || [stored boolValue];
        if ([sw respondsToSelector:@selector(setOnTintColor:)]) sw.onTintColor = kAccentBlue;
        [sw addTarget:self action:@selector(toggleFoxes:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    } else if (index.section == 0 && index.row < 3) {
        NSArray *keys = [NSArray arrayWithObjects:@"auto_connect", @"auto_reconnect", @"failover", nil];
        UISwitch *sw = [[[UISwitch alloc] init] autorelease];
        id value = [_settings objectForKey:[keys objectAtIndex:index.row]];
        sw.on = value ? [value boolValue] : YES; sw.enabled = _settings != nil; sw.tag = index.row;
        if ([sw respondsToSelector:@selector(setOnTintColor:)]) sw.onTintColor = kAccentBlue;
        [sw addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    } else if (index.section == 0) cell.detailTextLabel.text = [[_settings objectForKey:@"reconnect_max_attempts"] description] ?: @"5";
    else if ([name isEqualToString:@"Theme"]) cell.detailTextLabel.text = ShiroLocalizedText(ShiroThemeIsClassic() ? @"Classic" : @"Modern");
    else if ([name isEqualToString:@"Appearance"]) cell.detailTextLabel.text = ShiroLocalizedText(ShiroThemeIsLight() ? @"Light" : @"Dark");
    else if ([name isEqualToString:@"Language"]) cell.detailTextLabel.text = ShiroLanguageName();
    else if ([name isEqualToString:@"DNS"]) cell.detailTextLabel.text = [_settings objectForKey:@"dns"] ?: @"1.1.1.1";
    else if ([name isEqualToString:@"Registration proxy"]) cell.detailTextLabel.text = ShiroLocalizedText([_settings objectForKey:@"registration_proxy"] ?: @"Off");
    return cell;
}
- (void)preference:(NSString *)key value:(id)value {
    NSDictionary *request = [NSDictionary dictionaryWithObjectsAndKeys:@"preference", @"command", key, @"key", value, @"value", nil];
    [_ctl request:request reply:^(NSDictionary *response, NSString *error) {
        if (error) [self devSay:ShiroLocalizedText(@"Settings") message:ShiroHumanReadableError(error)];
        else { [_settings release]; _settings = [response copy]; }
        [_tv reloadData];
    }];
}
- (void)toggleFoxes:(UISwitch *)sw {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:sw.on forKey:@"ShiroFallingFoxes"];
    if (![defaults synchronize]) [self devSay:ShiroLocalizedText(@"Settings") message:ShiroLocalizedText(@"Could not save the setting")];
}
- (void)toggle:(UISwitch *)sw {
    [self preference:[[NSArray arrayWithObjects:@"auto_connect", @"auto_reconnect", @"failover", nil] objectAtIndex:sw.tag] value:[NSNumber numberWithBool:sw.on]];
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)index {
    [tv deselectRowAtIndexPath:index animated:YES];
    NSString *name = [[self rows:index.section] objectAtIndex:index.row];
    UIViewController *next = nil;
    if ([name isEqualToString:@"Theme"]) {
        ShiroDialogMenu(@"Theme", nil, [NSArray arrayWithObjects:@"Modern", @"Classic", nil], ^(NSInteger pick) {
            if (pick < 0) return;
            /* the modern theme keeps the id of 1.0.x installs, which is the default family */
            ShiroThemeApplyId(pick == 0 ? ShiroThemeDefaultId() : @"shiro-classic"); [_tv reloadData];
        });
    }
    else if ([name isEqualToString:@"Appearance"]) {
        ShiroDialogMenu(@"Appearance", nil, [NSArray arrayWithObjects:@"Light", @"Dark", nil], ^(NSInteger pick) {
            if (pick < 0) return;
            ShiroThemeSetLight(pick == 0); [_tv reloadData];
        });
    }
    else if ([name isEqualToString:@"System Logs"]) next = [[[ShiroLogsController alloc] init] autorelease];
    else if ([name isEqualToString:@"DNS"]) next = [[[ShiroRoutingVC alloc] initWithControl:_ctl] autorelease];
    else if ([name isEqualToString:@"Registration proxy"]) [self editRegistrationProxy];
    else if ([name isEqualToString:@"About"]) next = [[[ShiroAboutController alloc] init] autorelease];
    else if ([name isEqualToString:@"Developer settings"]) next = [[[ShiroDeveloperVC alloc] initWithControl:_ctl page:0] autorelease];
    else if ([name isEqualToString:@"Language"]) {
        ShiroDialogMenu(@"Language", nil, [NSArray arrayWithObjects:@"English", @"Русский", @"中文", nil], ^(NSInteger pick) {
            if (pick < 0) return;
            ShiroSetLanguage((ShiroLanguage)pick); self.title = ShiroLocalizedText(@"Settings"); [_tv reloadData];
        });
    } else if ([name isEqualToString:@"Reconnect attempts"]) {
        ShiroDialogMenu(name, nil, [NSArray arrayWithObjects:@"3", @"5", @"10", nil], ^(NSInteger pick) {
            if (pick < 0) return;
            [self preference:@"reconnect_max_attempts" value:[[NSArray arrayWithObjects:@3, @5, @10, nil] objectAtIndex:(NSUInteger)pick]];
        });
    } else if ([name isEqualToString:@"Backup"]) [self backupMenu];
    if (next) [self.navigationController pushViewController:next animated:YES];
}
- (void)editRegistrationProxy {
    if (!_settings) { [self devSay:ShiroLocalizedText(@"Registration proxy") message:ShiroLocalizedText(@"Daemon is unreachable")]; return; }
    if ([[_settings objectForKey:@"enabled"] boolValue]) {
        [self devSay:ShiroLocalizedText(@"Registration proxy") message:ShiroLocalizedText(@"Disconnect first")]; return;
    }
    ShiroDialogPrompt(@"Registration proxy", @"SOCKS5 or HTTP URL. Empty disables.",
        @"", nil, UIKeyboardTypeURL, @"Save", ^(NSString *text) {
        if (!text) return;
        NSDictionary *request = [NSDictionary dictionaryWithObjectsAndKeys:@"registrationProxy", @"command", text, @"url", nil];
        [_ctl request:request reply:^(NSDictionary *reply, NSString *error) {
            if (error) [self devSay:ShiroLocalizedText(@"Registration proxy") message:ShiroHumanReadableError(error)];
            else { [_settings release]; _settings = [reply copy]; }
            [_tv reloadData];
        }];
    });
}
- (void)backupMenu {
    ShiroDialogMenu(@"Backup", nil, [NSArray arrayWithObjects:@"Export", @"Import from clipboard", nil], ^(NSInteger pick) {
        if (pick == 0) [self exportBackup];
        else if (pick == 1) [self confirmRestore];
    });
}
- (void)exportBackup {
    if (!_settings) { [self devSay:ShiroLocalizedText(@"Backup") message:ShiroLocalizedText(@"Daemon is unreachable")]; return; }
    NSMutableDictionary *backup = [NSMutableDictionary dictionaryWithObject:@"shiro-settings-1" forKey:@"format"];
    for (NSString *key in [NSArray arrayWithObjects:@"direct", @"block", @"dns", @"trace", nil])
        if ([_settings objectForKey:key]) [backup setObject:[_settings objectForKey:key] forKey:key];
    NSData *data = [NSJSONSerialization dataWithJSONObject:backup options:NSJSONWritingPrettyPrinted error:NULL];
    [UIPasteboard generalPasteboard].string = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    [self devSay:ShiroLocalizedText(@"Backup") message:ShiroLocalizedText(@"Copied to clipboard")];
}
- (void)confirmRestore {
    ShiroDialogConfirm(@"Replace configuration?", @"Routing and DNS will be replaced by the backup in the clipboard. Disconnect first.",
                       @"Replace", NO, ^{ [self restoreBackup]; });
}
- (void)restoreBackup {
    NSString *text = [UIPasteboard generalPasteboard].string;
    if (text.length > 4096) { [self devSay:@"Backup" message:ShiroLocalizedText(@"Backup is too large")]; return; }
    id parsed = text ? [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL] : nil;
    if (![parsed isKindOfClass:[NSDictionary class]] || ![[parsed objectForKey:@"format"] isEqual:@"shiro-settings-1"]) {
        [self devSay:@"Backup" message:ShiroLocalizedText(@"Not a Shiro backup")]; return;
    }
    NSMutableDictionary *request = [[parsed mutableCopy] autorelease]; [request setObject:@"settings" forKey:@"command"];
    [_ctl request:request reply:^(NSDictionary *reply, NSString *error) { [self devSay:ShiroLocalizedText(@"Backup") message:error ?: ShiroLocalizedText(@"Configuration restored")]; }];
}
@end

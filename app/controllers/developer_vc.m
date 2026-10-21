#import "shiro_menus.h"
#import "app_common.h"
#import "ui_theme.h"
#import "crash_report.h"
#import "dev_console_vc.h"

@interface ShiroDeveloperVC () {
    NSInteger _page;
    NSDictionary *_snapshot;
    NSArray *_keys;
    BOOL _busy;
}
@end
@implementation ShiroDeveloperVC
- (id)initWithControl:(ShiroControl *)control page:(NSInteger)page {
    if ((self = [super initWithControl:control])) _page = page; return self;
}
- (void)dealloc { [_snapshot release]; [_keys release]; [super dealloc]; }
- (NSString *)devTitle {
    return ShiroLocalizedText([[NSArray arrayWithObjects:@"Developer settings", @"State", @"Checks", @"Force", @"Rescue", nil] objectAtIndex:_page]);
}
- (const char *)devScreenName { return "developer"; }
- (NSArray *)rows {
    if (_page == 0) return [NSArray arrayWithObjects:@"State", @"Checks", @"Force", @"Rescue", @"Console", nil];
    if (_page == 1) return _keys ?: [NSArray array];
    if (_page == 2) return [NSArray arrayWithObjects:@"Tunnel state", @"Tunnel routes", @"Diagnostics", nil];
    if (_page == 3) return [NSArray arrayWithObjects:@"Detailed trace", @"FPS overlay", nil];
    return [NSArray arrayWithObjects:@"App crash report", @"Safe mode", @"Diagnostics bundle", @"Clear logs", @"Reconnect", @"Reset WARP account", nil];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [_ctl request:[NSDictionary dictionaryWithObject:@"diagnostics" forKey:@"command"] reply:^(NSDictionary *response, NSString *error) {
        if (!error) {
            [_snapshot release]; _snapshot = [response copy]; [_keys release]; _keys = [[[response allKeys] sortedArrayUsingSelector:@selector(compare:)] retain];
        }
        [_tv reloadData];
    }];
}
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return [self rows].count; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell = [self devCellForTable:tv indexPath:index rows:[self rows].count];
    NSString *name = [[self rows] objectAtIndex:index.row]; cell.textLabel.text = ShiroLocalizedText(name);
    if (_page == 1) cell.detailTextLabel.text = [[_snapshot objectForKey:name] description];
    else if (_page == 0) {
        NSArray *details = [NSArray arrayWithObjects:@"Backend, tunnel, DNS, rules", @"Tunnel state and installed routes", @"Tracing and frame counter", @"Crash log, safe mode, diagnostics", @"Talk to the control socket without ssh", nil];
        cell.detailTextLabel.text = ShiroLocalizedText([details objectAtIndex:index.row]);
    }
    if (_page == 3) {
        UISwitch *sw = [[[UISwitch alloc] init] autorelease];
        sw.tag = index.row; sw.on = index.row == 0 ? [[_snapshot objectForKey:@"trace"] boolValue] : ShiroFPSOverlayEnabled();
        sw.enabled = index.row == 1 || _snapshot != nil;
        if ([sw respondsToSelector:@selector(setOnTintColor:)]) sw.onTintColor = kAccentBlue;
        [sw addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = sw;
    } else {
        ShiroStyleSelectableCell(cell); cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}
- (void)toggle:(UISwitch *)sw {
    if (sw.tag == 1) { ShiroFPSOverlaySetEnabled(sw.on); return; }
    BOOL previous = [[_snapshot objectForKey:@"trace"] boolValue]; sw.enabled = NO;
    [_ctl request:[NSDictionary dictionaryWithObjectsAndKeys:@"trace", @"command", [NSNumber numberWithBool:sw.on], @"trace", nil] reply:^(NSDictionary *response, NSString *error) {
        sw.enabled = YES;
        if (error) { [sw setOn:previous animated:YES]; [self devSay:[self devTitle] message:ShiroHumanReadableError(error)]; }
        else { [_snapshot release]; _snapshot = [response copy]; }
    }];
}
- (void)show:(NSString *)title text:(NSString *)body {
    ShiroTextController *screen = [[[ShiroTextController alloc] initWithTitle:ShiroLocalizedText(title) body:ShiroRedactSecrets(body ?: @"")] autorelease];
    [self.navigationController pushViewController:screen animated:YES];
}
- (void)request:(NSString *)command title:(NSString *)title {
    if (_busy) return; _busy = YES;
    [_ctl request:[NSDictionary dictionaryWithObject:command forKey:@"command"] reply:^(NSDictionary *reply, NSString *error) {
        _busy = NO;
        if (error) [self devSay:ShiroLocalizedText(title) message:ShiroHumanReadableError(error)];
        else [self show:title text:[reply objectForKey:@"routes"] ?: [reply description]];
    }];
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)index {
    [tv deselectRowAtIndexPath:index animated:YES];
    NSString *title = [[self rows] objectAtIndex:index.row];
    if (_page == 0) {
        UIViewController *next = index.row == 4 ? [[[ShiroConsoleController alloc] initWithControl:_ctl] autorelease] : [[[ShiroDeveloperVC alloc] initWithControl:_ctl page:index.row + 1] autorelease];
        [self.navigationController pushViewController:next animated:YES];
    } else if (_page == 1) [self show:title text:[[_snapshot objectForKey:title] description]];
    else if (_page == 2) [self request:index.row == 1 ? @"routes" : @"diagnostics" title:title];
    else if (_page == 4) {
        if (index.row == 0) [self show:title text:ShiroCrashLastReport() ?: ShiroLocalizedText(@"No app fault report")];
        else if (index.row == 1) [self devConfirm:ShiroLocalizedText(title) message:ShiroLocalizedText(@"Start with the stock appearance on the next launch?") button:ShiroLocalizedText(@"Enable") tag:1];
        else if (index.row == 2) [self request:@"diagnostics" title:title];
        else if (index.row == 3) [self devConfirm:ShiroLocalizedText(title) message:ShiroLocalizedText(@"Delete the daemon log?") button:ShiroLocalizedText(@"Clear") tag:3];
        else if (index.row == 4) [self request:@"reconnect" title:title];
        else [self devConfirm:ShiroLocalizedText(title) message:ShiroLocalizedText(@"Disconnect first. A new account will be registered on the next connection.") button:ShiroLocalizedText(@"Reset") tag:5];
    }
}
- (void)devConfirmed:(NSInteger)tag {
    if (tag == 1) { ShiroCrashEnterSafeMode(); [self devSay:[self devTitle] message:ShiroLocalizedText(@"Safe mode is enabled for the next launch")]; }
    else [self request:tag == 3 ? @"clearLogs" : @"resetAccount" title:[self devTitle]];
}
@end

@interface ShiroAccountVC () { NSDictionary *_snapshot; }
@end
@implementation ShiroAccountVC
- (void)dealloc { [_snapshot release]; [super dealloc]; }
- (NSString *)devTitle { return ShiroLocalizedText(@"WARP account"); }
- (const char *)devScreenName { return "warp account"; }
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [_ctl request:[NSDictionary dictionaryWithObject:@"diagnostics" forKey:@"command"] reply:^(NSDictionary *reply, NSString *error) {
        if (!error) { [_snapshot release]; _snapshot = [reply copy]; }
        [_tv reloadData];
    }];
}
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return 5; }
- (NSString *)devFooterForSection:(NSInteger)section { return ShiroLocalizedText(@"Private keys stay in the root-owned account file. The first connection registers an account with Cloudflare."); }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell = [self devCellForTable:tv indexPath:index rows:5];
    NSArray *titles = [NSArray arrayWithObjects:@"Provider", @"Protocol", @"Tunnel address", @"Endpoint", @"Reset WARP account", nil];
    cell.textLabel.text = ShiroLocalizedText([titles objectAtIndex:index.row]);
    if (index.row == 0) cell.detailTextLabel.text = @"Cloudflare WARP";
    else if (index.row == 1) cell.detailTextLabel.text = @"WireGuard";
    else if (index.row == 2 || index.row == 3) cell.detailTextLabel.text = [_snapshot objectForKey:index.row == 2 ? @"tunnel_address" : @"endpoint"] ?: ShiroLocalizedText(@"Not available yet");
    else { ShiroStyleSelectableCell(cell); cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; }
    return cell;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)index {
    [tv deselectRowAtIndexPath:index animated:YES];
    if (index.row == 4) [self devConfirm:ShiroLocalizedText(@"Reset WARP account") message:ShiroLocalizedText(@"Disconnect first. A new account will be registered on the next connection.") button:ShiroLocalizedText(@"Reset") tag:1];
}
- (void)devConfirmed:(NSInteger)tag {
    [_ctl request:[NSDictionary dictionaryWithObject:@"resetAccount" forKey:@"command"] reply:^(NSDictionary *reply, NSString *error) {
        [self devSay:[self devTitle] message:error ?: ShiroLocalizedText(@"Account reset")];
    }];
}
@end

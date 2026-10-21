#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#include <stdio.h>
#include <math.h>
#include <objc/message.h>
#import "control_client.h"
#import "ui_theme.h"
#import "app_common.h"
#import "card_kit.h"
#import "crash_report.h"
#include "shiro_paths.h"

static NSString *ShiroReadLogTail(NSString *path, long maxBytes) {
    FILE *file = fopen([path fileSystemRepresentation], "rb");
    if (!file) return nil;
    if (fseek(file, 0, SEEK_END) != 0) { fclose(file); return nil; }
    long size = ftell(file);
    if (size < 0) { fclose(file); return nil; }
    long start = size > maxBytes ? size - maxBytes : 0;
    if (fseek(file, start, SEEK_SET) != 0) { fclose(file); return nil; }
    size_t length = (size_t)(size - start);
    NSMutableData *data = [NSMutableData dataWithLength:length];
    size_t got = length ? fread([data mutableBytes], 1, length, file) : 0;
    fclose(file);
    [data setLength:got];
    NSString *text = [[[NSString alloc] initWithData:data
                                            encoding:NSUTF8StringEncoding] autorelease];
    if (!text) text = [[[NSString alloc] initWithData:data
                                             encoding:NSISOLatin1StringEncoding] autorelease];
    if (start > 0 && [text length]) {
        NSRange newline = [text rangeOfString:@"\n"];
        if (newline.location != NSNotFound)
            text = [text substringFromIndex:newline.location + 1];
    }
    return text;
}

static NSString *ShiroTagLegacyLog(NSString *text, NSString *source) {
    if (![text length]) return @"";
    NSMutableString *tagged = [NSMutableString string];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if (![line length]) continue;
        [tagged appendFormat:@"[%@] %@\n", source, line];
    }
    return tagged;
}

/* how a log line reads at a glance: faults in red, retries in amber, the bracket
   tags of the app and status bar in the accent */
typedef enum { ShiroLogLineNormal = 0, ShiroLogLineFault, ShiroLogLineWarn, ShiroLogLineTag } ShiroLogLineKind;

static BOOL ShiroLogLineHas(NSString *line, NSString *needle) {
    return [line rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static ShiroLogLineKind ShiroClassifyLogLine(NSString *line) {
    static NSString *const faults[] = { @"fail", @"error", @"cannot", @"refused", @"denied",
                                        @"crash", @"fault", @"killed", nil };
    static NSString *const warns[] = { @"warn", @"retry", @"timeout", @"timed out", @"lost",
                                       @"unreachable", nil };
    for (int i = 0; faults[i]; ++i)
        if (ShiroLogLineHas(line, faults[i])) return ShiroLogLineFault;
    for (int i = 0; warns[i]; ++i)
        if (ShiroLogLineHas(line, warns[i])) return ShiroLogLineWarn;
    if ([line hasPrefix:@"["]) return ShiroLogLineTag;
    return ShiroLogLineNormal;
}

/* nsforegroundcolorattributename is ios 6; the symbol is looked up so the same
   binary runs on ios 5 and 4.3, where the log stays one colour */
static NSString *ShiroLogColorKey(void) {
    NSString **key = (NSString **)dlsym(RTLD_DEFAULT, "NSForegroundColorAttributeName");
    return key ? *key : nil;
}

static NSString *ShiroLogFontKey(void) {
    NSString **key = (NSString **)dlsym(RTLD_DEFAULT, "NSFontAttributeName");
    return key ? *key : nil;
}

#define LOGS_SHEET_ACTIONS 1

@implementation ShiroLogsController {

    UITextView *_textView;
    UISegmentedControl *_filter;
    UISearchBar *_search;
    UILabel *_count;
    NSString *_allLogs;
    NSString *_shown;
    ShiroControl *_ctl;
    NSTimer *_reloadTimer;
    BOOL _loading;
    BOOL _logsVisible;
    NSUInteger _loadGeneration;

}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = ShiroLocalizedText(@"System Logs");
    ShiroApplyScreenChrome(self.view);

    UIBarButtonItem *refresh =
        [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                       target:self
                                                       action:@selector(loadLogs)] autorelease];
    UIBarButtonItem *actions =
        [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                       target:self
                                                       action:@selector(actionsPressed:)] autorelease];
/* ios 4.3 has one slot on the right: refresh keeps it, copy and share need two */
    if ([self.navigationItem respondsToSelector:@selector(setRightBarButtonItems:)])
        ((void (*)(id, SEL, id))objc_msgSend)(self.navigationItem,
            @selector(setRightBarButtonItems:), [NSArray arrayWithObjects:refresh, actions, nil]);
    else
        self.navigationItem.rightBarButtonItem = refresh;

    _filter = [[UISegmentedControl alloc] initWithItems:
               [NSArray arrayWithObjects:ShiroLocalizedText(@"all"), @"shirod",
                                         @"app", @"status", nil]];
    _filter.selectedSegmentIndex = 0;
    [_filter addTarget:self action:@selector(filterChanged:)
      forControlEvents:UIControlEventValueChanged];
    ShiroStyleGlassSegmented(_filter);
    [self.view addSubview:_filter];

    _search = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, 320.0f, 44.0f)];
    _search.delegate = self;
    _search.placeholder = ShiroLocalizedText(@"Search logs");
    _search.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _search.autocorrectionType = UITextAutocorrectionTypeNo;
    [self.view addSubview:_search];

    _count = [[UILabel alloc] initWithFrame:CGRectZero];
    _count.backgroundColor = [UIColor clearColor];
    _count.font = ShiroFontBody(12.0f, NO);
    _count.textColor = kInkMuted;
    _count.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:_count];

    UIView *plate = [[[UIView alloc] initWithFrame:CGRectZero] autorelease];
    plate.tag = 7701;
    plate.layer.cornerRadius = ShiroThemeCardRadius();
    plate.layer.borderWidth = 0;
    plate.layer.borderColor = [UIColor clearColor].CGColor;
    plate.opaque = NO;
    ShiroStyleTerminalPlate(plate);
    [self.view addSubview:plate];

    _textView = [[UITextView alloc] initWithFrame:CGRectZero];
    _textView.editable = NO;
    _textView.font = [UIFont fontWithName:@"Courier" size:11.0f];
    ShiroStyleTerminalText(_textView);
    [plate addSubview:_textView];

    [self layoutLogs];
}

- (void)layoutLogs {
    CGRect b = ShiroViewBounds(self.view);
    if (b.size.width < 2.0f || b.size.height < 2.0f) return;
    UIView *bg = [self.view viewWithTag:9111];
    if (bg) bg.frame = b;
    UIView *plate = [self.view viewWithTag:7701];
    if (!plate) return;
    CGFloat pad = 12.0f;
    CGFloat width = b.size.width - pad * 2.0f;
    CGFloat column = ShiroCardColumnWidth(b.size.width);
    if (column + 32.0f < b.size.width) { pad = floorf((b.size.width - column) * 0.5f); width = column; }
    _filter.frame = CGRectMake(pad, 8.0f, width, 30.0f);
    _search.frame = CGRectMake(pad - 4.0f, 42.0f, width + 8.0f, 44.0f);
    CGFloat footer = 22.0f;
    CGFloat top = 90.0f;
    plate.frame = CGRectMake(pad, top, width, b.size.height - top - footer - 8.0f);
    _count.frame = CGRectMake(pad, CGRectGetMaxY(plate.frame) + 2.0f, width, 18.0f);
    _textView.frame = CGRectInset(plate.bounds, 6, 6);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    ShiroCrashScreen("system logs");
    ShiroApplyScreenChrome(self.view);
    ShiroStyleGlassSegmented(_filter);
    [self layoutLogs];
    _logsVisible = YES;
    if (!_reloadTimer) _reloadTimer = [[NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(loadLogs) userInfo:nil repeats:YES] retain];
    [self loadLogs];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    _logsVisible = NO;
    ++_loadGeneration;
    _loading = NO;
    [_reloadTimer invalidate]; [_reloadTimer release]; _reloadTimer = nil;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutLogs];
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)io
                                         duration:(NSTimeInterval)dur {
    (void)io; (void)dur;
    [self layoutLogs];
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)io {
    (void)io;
    [self layoutLogs];
}

- (void)dealloc {
    [_reloadTimer invalidate]; [_reloadTimer release];
    _search.delegate = nil;
    [_textView release];
    [_filter release];
    [_search release];
    [_count release];
    [_shown release];
    [_allLogs release];
    [_ctl release];
    [super dealloc];
}

- (void)showLogText:(NSString *)content {
    NSString *safe = ShiroRedactSecrets(content ? content : @"");
    if ([_allLogs isEqualToString:safe]) return;
    [_allLogs release];
    _allLogs = [safe copy];
    [self filterChanged:_filter];
}

/* the daemon log cannot hold an app crash: the app is dead before it could
   send one, so the report the crash handler left on disk is folded in here */
static NSString *ShiroAppCrashSection(void) {
    NSString *report = ShiroCrashLastReport();
    BOOL safe = ShiroCrashSafeMode();
    if (![report length] && !safe) return @"";
/* the version the report names is the build that crashed, which is not always
   the build reading it: an update installed over a crash leaves the old report
   in place until this one proves it can start */
    BOOL foreign = [report length] &&
                   [report rangeOfString:SHIRO_VERSION].location == NSNotFound;
    NSMutableString *tagged = [NSMutableString stringWithString:
        foreign ? @"[app] --- an earlier build crashed here; this one has not ---\n"
                : @"[app] --- previous launch failed ---\n"];
    [tagged appendFormat:@"[app] running: shiro %@\n", SHIRO_VERSION];
    if (safe)
        [tagged appendFormat:@"[app] safe mode active: %d launches in a row "
                              "never reached the first frame\n",
                             ShiroCrashFailedLaunches()];
    for (NSString *line in [report componentsSeparatedByString:@"\n"]) {
        if (![line length]) continue;
        [tagged appendFormat:@"[app] %@\n", line];
    }
    [tagged appendString:@"[app] --- end of report ---\n"];
    return tagged;
}

/* springboard writes which status bar it found and whether the vpn badge could
   be shown without touching the wifi glyph; the app cannot see its log.
   this is an append-only ring now, so the tail can show the sequence that
   led up to a wifi glyph report, not just the last state */
static NSString *ShiroStatusSection(void) {
    NSString *tail = ShiroReadLogTail(
        @"/var/mobile/Library/Preferences/com.shiro.status.log", 8000);
    if (![tail length]) return @"[status bar] no extension log yet; restart SpringBoard after installing Shiro\n";
    NSMutableString *tagged = [NSMutableString string];
    for (NSString *line in [tail componentsSeparatedByString:@"\n"]) {
        if (![line length]) continue;
        [tagged appendFormat:@"[status bar] %@\n", line];
    }
    return tagged;
}

- (void)loadLogs {
    if (!_logsVisible || _loading) return;
    _loading = YES;
    NSUInteger generation = ++_loadGeneration;
    NSMutableString *local = [NSMutableString string];
    [local appendString:ShiroTagLegacyLog(ShiroReadLogTail(@SHIRO_APP_LOG ".1", 16000), @"app")];
    [local appendString:ShiroTagLegacyLog(ShiroReadLogTail(@SHIRO_APP_LOG, 24000), @"app")];
    [local appendString:ShiroAppCrashSection()];
    [local appendString:ShiroStatusSection()];
    if (![_allLogs length]) [self showLogText:local];
    /* shirod owns its root-only log, so even a readable old file is not authoritative */
    if (!_ctl) _ctl = [[ShiroControl alloc] initWithSocketPath:SHIRO_SOCK];
    [_ctl request:[NSDictionary dictionaryWithObject:@"logs" forKey:@"command"] reply:^(NSDictionary *response, NSString *error) {
        if (generation != _loadGeneration || !_logsVisible) return;
        _loading = NO;
        NSString *daemon = [response objectForKey:@"logs"];
        if (error) daemon = [NSString stringWithFormat:@"unavailable: %@", error];
        else if (![daemon length]) daemon = @"no daemon log entries";
        [self showLogText:[local stringByAppendingString:ShiroTagLegacyLog(daemon, @"shirod")]];
    }];
}

/* the lines of the chosen source that hold the search text */
- (NSString *)filteredLogText {
    NSInteger selected = _filter.selectedSegmentIndex;
    NSString *query = [_search.text stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableString *shown = [NSMutableString string];
    for (NSString *line in [_allLogs componentsSeparatedByString:@"\n"]) {
        if (![line length]) continue;
        if (selected != 0) {
            BOOL isApp = [line hasPrefix:@"[app]"];
            BOOL isStatus = [line hasPrefix:@"[status bar]"];
            BOOL keep = (selected == 2 && isApp) || (selected == 1 && !isApp && !isStatus) || (selected == 3 && isStatus);
            if (!keep) continue;
        }
        if ([query length] && !ShiroLogLineHas(line, query)) continue;
        [shown appendFormat:@"%@\n", line];
    }
    return shown;
}

- (UIColor *)colorForKind:(ShiroLogLineKind)kind {
    BOOL light = ShiroThemeIsLight();
    switch (kind) {
        case ShiroLogLineFault:
            return light ? [UIColor colorWithRed:0.76f green:0.17f blue:0.14f alpha:1.0f]
                         : [UIColor colorWithRed:1.00f green:0.45f blue:0.40f alpha:1.0f];
        case ShiroLogLineWarn:
            return light ? [UIColor colorWithRed:0.69f green:0.42f blue:0.02f alpha:1.0f]
                         : [UIColor colorWithRed:1.00f green:0.75f blue:0.30f alpha:1.0f];
        case ShiroLogLineTag:
            return light ? kAccentBlue : ShiroShadeColor(kAccentBlue, 0.25f);
        default:
            return _textView.textColor;
    }
}

/* each line is coloured by what it says. ios 6 and later take attributed text in
   a text view; before that the log is one colour, as it always was */
- (void)showText:(NSString *)text {
    NSString *colorKey = ShiroLogColorKey();
    NSString *fontKey = ShiroLogFontKey();
    if (![_textView respondsToSelector:@selector(setAttributedText:)] || !colorKey || !fontKey ||
        ![text length]) {
        _textView.text = text;
        return;
    }
    NSMutableAttributedString *attributed = [[[NSMutableAttributedString alloc]
                                              initWithString:text] autorelease];
    [attributed addAttribute:fontKey value:_textView.font range:NSMakeRange(0, [text length])];
    NSUInteger at = 0;
    UIColor *base = _textView.textColor;
    while (at < [text length]) {
        NSRange eol = [text rangeOfString:@"\n" options:0
                                    range:NSMakeRange(at, [text length] - at)];
        NSUInteger end = eol.location == NSNotFound ? [text length] : eol.location + 1;
        NSRange range = NSMakeRange(at, end - at);
        ShiroLogLineKind kind = ShiroClassifyLogLine([text substringWithRange:range]);
        UIColor *color = kind == ShiroLogLineNormal ? base : [self colorForKind:kind];
        [attributed addAttribute:colorKey value:color range:range];
        at = end;
    }
    ((void (*)(id, SEL, id))objc_msgSend)(_textView, @selector(setAttributedText:), attributed);
}

- (void)filterChanged:(UISegmentedControl *)sender {
    (void)sender;
    BOOL follow = _textView.contentSize.height <= _textView.bounds.size.height ||
        _textView.contentOffset.y + _textView.bounds.size.height >= _textView.contentSize.height - 44.0f;
    if (![_allLogs length]) {
        [_shown release];
        _shown = nil;
        _textView.text = ShiroLocalizedText(@"No daemon logs available");
        _count.text = @"";
        return;
    }
    NSString *shown = [self filteredLogText];
    NSInteger lines = 0;
    for (NSString *line in [shown componentsSeparatedByString:@"\n"])
        if ([line length]) ++lines;
    [_shown release];
    _shown = lines ? [shown copy] : nil;
    [self showText:shown];
    _count.textColor = kInkMuted;
    _count.text = lines ? [NSString stringWithFormat:ShiroLocalizedText(@"Lines: %d"), (int)lines] : @"";
    if (follow && [_textView.text length] > 0) {
        NSRange range = NSMakeRange([_textView.text length] - 1, 1);
        [_textView scrollRangeToVisible:range];
    }
}

- (void)searchBar:(UISearchBar *)bar textDidChange:(NSString *)text {
    (void)bar; (void)text;
    [self filterChanged:_filter];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)bar {
    [bar resignFirstResponder];
}

- (void)actionsPressed:(id)sender {
    (void)sender;
    if (![_shown length]) return;
    BOOL canShare = NSClassFromString(@"UIActivityViewController") != nil;
    UIActionSheet *sheet = [[UIActionSheet alloc]
             initWithTitle:nil
                  delegate:self
         cancelButtonTitle:ShiroLocalizedText(@"Cancel")
    destructiveButtonTitle:nil
         otherButtonTitles:ShiroLocalizedText(@"Copy"),
                           canShare ? ShiroLocalizedText(@"Share") : nil, nil];
    sheet.tag = LOGS_SHEET_ACTIONS;
    [sheet showInView:self.view];
    [sheet release];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
    if (sheet.tag != LOGS_SHEET_ACTIONS || index == sheet.cancelButtonIndex || ![_shown length])
        return;
    if (index == 0) {
        [UIPasteboard generalPasteboard].string = _shown;
        return;
    }
    Class activity = NSClassFromString(@"UIActivityViewController");
    if (!activity) return;
    id controller = [[[activity alloc] performSelector:@selector(initWithActivityItems:applicationActivities:)
                                            withObject:[NSArray arrayWithObject:_shown]
                                            withObject:nil] autorelease];
/* an ipad from ios 8 refuses to present the sheet without an anchor */
    id popover = [controller respondsToSelector:@selector(popoverPresentationController)]
        ? [controller performSelector:@selector(popoverPresentationController)] : nil;
    if (popover) {
        [popover setValue:self.view forKey:@"sourceView"];
        [popover setValue:[NSValue valueWithCGRect:CGRectMake(CGRectGetMidX(self.view.bounds),
                                                              self.view.bounds.size.height - 1.0f,
                                                              1.0f, 1.0f)]
                   forKey:@"sourceRect"];
    }
    [self presentViewController:controller animated:YES completion:nil];
}

@end

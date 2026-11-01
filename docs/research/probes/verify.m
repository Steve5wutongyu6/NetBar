#import "NBSystemWiFiMenu.h"
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
static int has(CFStringRef needle){
  pid_t cc=0;for(NSRunningApplication*a in NSWorkspace.sharedWorkspace.runningApplications)if([a.bundleIdentifier isEqualToString:@"com.apple.controlcenter"])cc=a.processIdentifier;
  if(!cc)return -1;
  AXUIElementRef app=AXUIElementCreateApplication(cc);CFArrayRef w=NULL;
  int n=0;if(AXUIElementCopyAttributeValue(app,kAXWindowsAttribute,(CFTypeRef*)&w)==0&&w){
    CFMutableArrayRef stack=CFArrayCreateMutable(NULL,0,&kCFTypeArrayCallBacks);
    for(CFIndex i=0;i<CFArrayGetCount(w);i++)CFArrayAppendValue(stack,CFArrayGetValueAtIndex(w,i));
    while(CFArrayGetCount(stack)){CFIndex last=CFArrayGetCount(stack)-1;AXUIElementRef el=(AXUIElementRef)CFArrayGetValueAtIndex(stack,last);CFRetain(el);CFArrayRemoveValueAtIndex(stack,last);
      CFStringRef role=NULL,desc=NULL;AXUIElementCopyAttributeValue(el,kAXRoleAttribute,(CFTypeRef*)&role);AXUIElementCopyAttributeValue(el,kAXDescriptionAttribute,(CFTypeRef*)&desc);
      if((role&&CFStringFind(role,needle,0).location!=kCFNotFound)||(desc&&CFStringFind(desc,needle,0).location!=kCFNotFound)){printf("  found \"%s\"\n",[(__bridge NSString*)(desc?:role) UTF8String]);n++;}
      if(role)CFRelease(role);if(desc)CFRelease(desc);
      CFArrayRef kids=NULL;if(AXUIElementCopyAttributeValue(el,kAXChildrenAttribute,(CFTypeRef*)&kids)==0&&kids){for(CFIndex j=0;j<CFArrayGetCount(kids);j++)CFArrayAppendValue(stack,CFArrayGetValueAtIndex(kids,j));CFRelease(kids);}
      CFRelease(el);}
    CFRelease(stack);CFRelease(w);}
  CFRelease(app);return n;}
static void esc(void){CGEventRef d=CGEventCreateKeyboardEvent(NULL,(CGKeyCode)53,true);CGEventRef u=CGEventCreateKeyboardEvent(NULL,(CGKeyCode)53,false);CGEventPost(kCGHIDEventTap,d);CGEventPost(kCGHIDEventTap,u);if(d)CFRelease(d);if(u)CFRelease(u);}
int main(void){ @autoreleasepool {
  printf("before: Known Networks=%d\n",has(CFSTR("Known Networks")));
  NBSystemWiFiMenuOutcome o=[NBSystemWiFiMenu openSystemWiFiMenu];
  printf("outcome=%ld\n",(long)o);usleep(900000);
  int k=has(CFSTR("Known Networks")), oth=has(CFSTR("Other Networks")), ph=has(CFSTR("Personal Hotspot")), set=has(CFSTR("Settings"));
  printf("after: Known Networks=%d Other Networks=%d Personal Hotspot=%d Settings=%d\n",k,oth,ph,set);
  printf("%s\n", (k>0&&oth>0)?"SYSTEM WIFI MENU IS OPEN":"NOT OPEN");
  usleep(600000);esc();usleep(300000);esc();
} return 0;}
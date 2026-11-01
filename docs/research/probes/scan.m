#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
static const char *cs(CFStringRef s){static char b[256];if(!s)return"-";if(!CFStringGetCString(s,b,sizeof(b),kCFStringEncodingUTF8))return"?";return b;}
int main(void){ @autoreleasepool {
  double W=CGDisplayBounds(CGMainDisplayID()).size.width;
  AXUIElementRef sys=AXUIElementCreateSystemWide();
  NSMutableDictionary *seen=[NSMutableDictionary dictionary];
  for(double x=0;x<W;x+=2){
    AXUIElementRef el=NULL;
    if(AXUIElementCopyElementAtPosition(sys,x,12,&el)!=0||!el)continue;
    CFStringRef role=NULL,desc=NULL;pid_t pid=0;
    AXUIElementCopyAttributeValue(el,kAXRoleAttribute,(CFTypeRef*)&role);
    AXUIElementCopyAttributeValue(el,kAXDescriptionAttribute,(CFTypeRef*)&desc);
    AXUIElementGetPid(el,&pid);
    NSString *key=[NSString stringWithFormat:@"%d|%s|%s",pid,cs(role),cs(desc)];
    if(!seen[key]){
      CGRect fr=CGRectNull;CFTypeRef t=NULL;
      if(AXUIElementCopyAttributeValue(el,kAXPositionAttribute,(CFTypeRef*)&t)==0&&t){CGPoint p;AXValueGetValue((AXValueRef)t,kAXValueCGPointType,&p);fr.origin=p;CFRelease(t);}
      t=NULL;
      if(AXUIElementCopyAttributeValue(el,kAXSizeAttribute,(CFTypeRef*)&t)==0&&t){CGSize s;AXValueGetValue((AXValueRef)t,kAXValueCGSizeType,&s);fr.size=s;CFRelease(t);}
      seen[key]=@(x);
      printf("x=%.0f pid=%d role='%s' desc='%s' pos=(%.0f,%.0f) size=(%.0fx%.0f)\n",x,pid,cs(role),cs(desc),fr.origin.x,fr.origin.y,fr.size.width,fr.size.height);
    }
    if(role)CFRelease(role);if(desc)CFRelease(desc);CFRelease(el);
  }
  printf("distinct=%lu\n",(unsigned long)seen.count);
} return 0;}
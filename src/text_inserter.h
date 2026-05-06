#pragma once
#import <ApplicationServices/ApplicationServices.h>
#include <string>

void           heu_check_ax_permission(void);
AXUIElementRef heu_capture_focused_element(void);  // +1 retained or nullptr
bool           heu_insert_text(AXUIElementRef element, const std::string & text);

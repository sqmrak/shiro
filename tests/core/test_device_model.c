#include "shiro_device_model.h"

#include <assert.h>
#include <string.h>

int main(void) {
    assert(strcmp(shiro_device_model_name("iPhone10,3"), "iPhone X") == 0);
    assert(strcmp(shiro_device_model_name("iPhone10,6"), "iPhone X") == 0);
    assert(strcmp(shiro_device_model_name("iPad2,1"), "iPad 2") == 0);
    assert(shiro_device_model_name("iPhone99,1") == NULL);
    assert(shiro_device_model_name(NULL) == NULL);
    return 0;
}

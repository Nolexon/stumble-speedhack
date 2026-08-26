#include <stdio.h>
#include <dlfcn.h>
#include "fishhook.h"

static void (*orig_set_timeScale)(float);

void hooked_set_timeScale(float value) {
    if (orig_set_timeScale) {
        orig_set_timeScale(value * 2.0f);
    }
}

__attribute__((constructor))
static void init(void) {
    struct rebinding rebindings[] = {
        {"_UnityEngine_Time_set_timeScale", hooked_set_timeScale, (void **)&orig_set_timeScale},
        {"UnityEngine_Time_set_timeScale", hooked_set_timeScale, (void **)&orig_set_timeScale}
    };
    rebind_symbols(rebindings, 2);
}
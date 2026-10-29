#pragma once
#define IDI_APP 101
#ifndef VIKEY_VERSION
#define VIKEY_VERSION "0.1.0"
#endif
#define VIKEY_W2(x) L##x
#define VIKEY_W(x) VIKEY_W2(x)
#define VIKEY_VERSION_W VIKEY_W(VIKEY_VERSION)

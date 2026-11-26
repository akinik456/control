#pragma once
#include <Arduino.h>

void FirebaseSession_Begin();
void FirebaseSession_Poll();
const String& FirebaseSession_Uid();
const String& FirebaseSession_IdToken();

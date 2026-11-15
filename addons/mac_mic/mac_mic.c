// mac_mic: makes the Mac's built-in microphone the system input, so Godot opens it at launch.
//
// Godot 4.7's CoreAudio driver fixes the microphone's sample rate from the Mac's default input when the game starts;
// switching microphone inside the game then delivers almost nothing. A Bluetooth speaker or headset as the default
// input (8 kHz call mode) made voice chat silent. The game runs this before audio starts (editor: before Play; game:
// at launch, restarting once).
//
//   mac_mic get       prints the current default input's name
//   mac_mic builtin   makes the built-in microphone the default input; prints "already <name>" or
//                     "switched <old>|<new>"; exit 2 when the Mac has no built-in microphone
//
// Build (universal):  clang -O2 -arch arm64 -arch x86_64 -framework CoreAudio -framework CoreFoundation \
//                     -o addons/mac_mic/mac_mic addons/mac_mic/mac_mic.c
#include <CoreAudio/CoreAudio.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static AudioObjectPropertyAddress addr(AudioObjectPropertySelector sel, AudioObjectPropertyScope scope) {
	AudioObjectPropertyAddress a = { sel, scope, kAudioObjectPropertyElementMain };
	return a;
}

static AudioDeviceID default_input(void) {
	AudioDeviceID id = kAudioObjectUnknown;
	UInt32 size = sizeof(id);
	AudioObjectPropertyAddress a = addr(kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeGlobal);
	AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &size, &id);
	return id;
}

static void device_name(AudioDeviceID id, char *out, size_t n) {
	out[0] = 0;
	CFStringRef name = NULL;
	UInt32 size = sizeof(name);
	AudioObjectPropertyAddress a = addr(kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal);
	if (AudioObjectGetPropertyData(id, &a, 0, NULL, &size, &name) == noErr && name != NULL) {
		CFStringGetCString(name, out, (CFIndex)n, kCFStringEncodingUTF8);
		CFRelease(name);
	}
}

static UInt32 input_channels(AudioDeviceID id) {
	AudioObjectPropertyAddress a = addr(kAudioDevicePropertyStreamConfiguration, kAudioDevicePropertyScopeInput);
	UInt32 size = 0;
	if (AudioObjectGetPropertyDataSize(id, &a, 0, NULL, &size) != noErr || size == 0)
		return 0;
	AudioBufferList *list = (AudioBufferList *)malloc(size);
	UInt32 channels = 0;
	if (AudioObjectGetPropertyData(id, &a, 0, NULL, &size, list) == noErr)
		for (UInt32 i = 0; i < list->mNumberBuffers; i++)
			channels += list->mBuffers[i].mNumberChannels;
	free(list);
	return channels;
}

static int is_builtin(AudioDeviceID id) {
	UInt32 transport = 0, size = sizeof(transport);
	AudioObjectPropertyAddress a = addr(kAudioDevicePropertyTransportType, kAudioObjectPropertyScopeGlobal);
	return AudioObjectGetPropertyData(id, &a, 0, NULL, &size, &transport) == noErr
		&& transport == kAudioDeviceTransportTypeBuiltIn;
}

static AudioDeviceID builtin_input(void) {
	AudioObjectPropertyAddress a = addr(kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal);
	UInt32 size = 0;
	if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &a, 0, NULL, &size) != noErr)
		return kAudioObjectUnknown;
	AudioDeviceID *ids = (AudioDeviceID *)malloc(size);
	AudioDeviceID found = kAudioObjectUnknown;
	if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &size, ids) == noErr)
		for (UInt32 i = 0; i < size / sizeof(AudioDeviceID) && found == kAudioObjectUnknown; i++)
			if (is_builtin(ids[i]) && input_channels(ids[i]) > 0)
				found = ids[i];
	free(ids);
	return found;
}

int main(int argc, char **argv) {
	char cur[256], want[256];
	AudioDeviceID current = default_input();
	device_name(current, cur, sizeof(cur));
	if (argc < 2 || strcmp(argv[1], "get") == 0) {
		printf("%s\n", cur);
		return 0;
	}
	if (strcmp(argv[1], "builtin") != 0) {
		fprintf(stderr, "usage: mac_mic get | builtin\n");
		return 1;
	}
	AudioDeviceID mic = builtin_input();
	if (mic == kAudioObjectUnknown) {
		printf("none\n");
		return 2;
	}
	device_name(mic, want, sizeof(want));
	if (mic == current) {
		printf("already %s\n", want);
		return 0;
	}
	AudioObjectPropertyAddress a = addr(kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeGlobal);
	OSStatus err = AudioObjectSetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, sizeof(mic), &mic);
	if (err != noErr) {
		fprintf(stderr, "could not set the input (%d)\n", (int)err);
		return 1;
	}
	printf("switched %s|%s\n", cur, want);
	return 0;
}

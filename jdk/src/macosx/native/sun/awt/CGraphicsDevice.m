/*
 * Copyright (c) 2012, Oracle and/or its affiliates. All rights reserved.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.  Oracle designates this
 * particular file as subject to the "Classpath" exception as provided
 * by Oracle in the LICENSE file that accompanied this code.
 *
 * This code is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * version 2 for more details (a copy is included in the LICENSE file that
 * accompanied this code).
 *
 * You should have received a copy of the GNU General Public License version
 * 2 along with this work; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * Please contact Oracle, 500 Oracle Parkway, Redwood Shores, CA 94065 USA
 * or visit www.oracle.com if you need additional information or have any
 * questions.
 */

#include "LWCToolkit.h"

/*
 * Convert the mode string to the more convinient bits per pixel value
 */
static int getBPPFromModeString(CFStringRef mode) 
{
    if ((CFStringCompare(mode, CFSTR(kIO30BitDirectPixels), kCFCompareCaseInsensitive) == kCFCompareEqualTo)) {
        // This is a strange mode, where we using 10 bits per RGB component and pack it into 32 bits
        // Java is not ready to work with this mode but we have to specify it as supported
        return 30;
    }
    else if (CFStringCompare(mode, CFSTR(IO32BitDirectPixels), kCFCompareCaseInsensitive) == kCFCompareEqualTo) {
        return 32;
    }
    else if (CFStringCompare(mode, CFSTR(IO16BitDirectPixels), kCFCompareCaseInsensitive) == kCFCompareEqualTo) {
        return 16;
    }
    else if (CFStringCompare(mode, CFSTR(IO8BitIndexedPixels), kCFCompareCaseInsensitive) == kCFCompareEqualTo) {
        return 8;
    }
    
    return 0;
}

/*
 * Find the best possible match in the list of display modes that we can switch to based on
 * the provided parameters.
 */
static CGDisplayModeRef getBestModeForParameters(CFArrayRef allModes, int w, int h, int bpp, int refrate) {
    CGDisplayModeRef bestGuess = NULL;
    CFIndex numModes = CFArrayGetCount(allModes), n;
    int thisBpp = 0;
    for(n = 0; n < numModes; n++ ) {
        CGDisplayModeRef cRef = (CGDisplayModeRef) CFArrayGetValueAtIndex(allModes, n);
        if(cRef == NULL) {
            continue;
        }
        CFStringRef modeString = CGDisplayModeCopyPixelEncoding(cRef);
        thisBpp = getBPPFromModeString(modeString);
        CFRelease(modeString);
        if (thisBpp != bpp || (int)CGDisplayModeGetHeight(cRef) != h || (int)CGDisplayModeGetWidth(cRef) != w) {
            // One of the key parameters does not match
            continue;
        }
        // Refresh rate might be 0 in display mode and we ask for specific display rate
        // but if we do not find exact match then 0 refresh rate might be just Ok
        if (CGDisplayModeGetRefreshRate(cRef) == refrate) {
            // Exact match
            return cRef;
        }
        if (CGDisplayModeGetRefreshRate(cRef) == 0) {
            // Not exactly what was asked for, but may fit our needs if we don't find an exact match
            bestGuess = cRef;
        }
    }
    return bestGuess;
}

/*
 * Create a new java.awt.DisplayMode instance based on provided CGDisplayModeRef
 */
static jobject createJavaDisplayMode(CGDisplayModeRef mode, JNIEnv *env, jint displayID) {
    jobject ret = NULL;
    jint h, w, bpp, refrate;
    JNF_COCOA_ENTER(env);
    CFStringRef currentBPP = CGDisplayModeCopyPixelEncoding(mode);
    bpp = getBPPFromModeString(currentBPP);
    refrate = CGDisplayModeGetRefreshRate(mode);
    h = CGDisplayModeGetHeight(mode);
    w = CGDisplayModeGetWidth(mode);
    CFRelease(currentBPP);
    static JNF_CLASS_CACHE(jc_DisplayMode, "java/awt/DisplayMode");
    static JNF_CTOR_CACHE(jc_DisplayMode_ctor, jc_DisplayMode, "(IIII)V");
    ret = JNFNewObject(env, jc_DisplayMode_ctor, w, h, bpp, refrate);
    JNF_COCOA_EXIT(env);
    return ret;
}


/*
 * Class:     sun_awt_CGraphicsDevice
 * Method:    nativeGetXResolution
 * Signature: (I)D
 */
JNIEXPORT jdouble JNICALL
Java_sun_awt_CGraphicsDevice_nativeGetXResolution
  (JNIEnv *env, jclass class, jint displayID)
{
    // TODO: this is the physically correct answer, but we probably want
    // to use NSScreen API instead...
    CGSize size = CGDisplayScreenSize(displayID);
    CGRect rect = CGDisplayBounds(displayID);
    // 1 inch == 25.4 mm
    jfloat inches = size.width / 25.4f;
    jfloat dpi = rect.size.width / inches;
    return dpi;
}

/*
 * Class:     sun_awt_CGraphicsDevice
 * Method:    nativeGetYResolution
 * Signature: (I)D
 */
JNIEXPORT jdouble JNICALL
Java_sun_awt_CGraphicsDevice_nativeGetYResolution
  (JNIEnv *env, jclass class, jint displayID)
{
    // TODO: this is the physically correct answer, but we probably want
    // to use NSScreen API instead...
    CGSize size = CGDisplayScreenSize(displayID);
    CGRect rect = CGDisplayBounds(displayID);
    // 1 inch == 25.4 mm
    jfloat inches = size.height / 25.4f;
    jfloat dpi = rect.size.height / inches;
    return dpi;
}

/*
 * Class:     sun_awt_CGraphicsDevice
 * Method:    nativeSetDisplayMode
 * Signature: (IIIII)V
 */
JNIEXPORT void JNICALL
Java_sun_awt_CGraphicsDevice_nativeSetDisplayMode
(JNIEnv *env, jclass class, jint displayID, jint w, jint h, jint bpp, jint refrate)
{
    JNF_COCOA_ENTER(env);
    CFArrayRef allModes = CGDisplayCopyAllDisplayModes(displayID, NULL);
    CGDisplayModeRef closestMatch = getBestModeForParameters(allModes, (int)w, (int)h, (int)bpp, (int)refrate);
    if (closestMatch != NULL) {
        [JNFRunLoop performOnMainThreadWaiting:YES withBlock:^(){
            CGDisplayConfigRef config;
            CGError retCode = CGBeginDisplayConfiguration(&config);
            if (retCode == kCGErrorSuccess) {
                CGConfigureDisplayWithDisplayMode(config, displayID, closestMatch, NULL);
                CGCompleteDisplayConfiguration(config, kCGConfigureForAppOnly);
                if (config != NULL) {
                    CFRelease(config);
                }
            }
        }];
    }
    CFRelease(allModes);
    JNF_COCOA_EXIT(env);
}

/*
 * Class:     sun_awt_CGraphicsDevice
 * Method:    nativeGetDisplayMode
 * Signature: (I)Ljava/awt/DisplayMode
 */
JNIEXPORT jobject JNICALL
Java_sun_awt_CGraphicsDevice_nativeGetDisplayMode
(JNIEnv *env, jclass class, jint displayID)
{
    jobject ret = NULL;
    CGDisplayModeRef currentMode = CGDisplayCopyDisplayMode(displayID);
    ret = createJavaDisplayMode(currentMode, env, displayID);
    CGDisplayModeRelease(currentMode);
    return ret;
}

/*
 * Class:     sun_awt_CGraphicsDevice
 * Method:    nativeGetDisplayMode
 * Signature: (I)[Ljava/awt/DisplayModes
 */
JNIEXPORT jobjectArray JNICALL
Java_sun_awt_CGraphicsDevice_nativeGetDisplayModes
(JNIEnv *env, jclass class, jint displayID)
{
    jobjectArray jreturnArray = NULL;
    JNF_COCOA_ENTER(env);
    CFArrayRef allModes = CGDisplayCopyAllDisplayModes(displayID, NULL);
    CFIndex numModes = CFArrayGetCount(allModes);
    static JNF_CLASS_CACHE(jc_DisplayMode, "java/awt/DisplayMode");

    jreturnArray = JNFNewObjectArray(env, &jc_DisplayMode, (jsize) numModes);
    if (!jreturnArray) {
        NSLog(@"CGraphicsDevice can't create java array of DisplayMode objects");
        return nil;
    }

    CFIndex n;
    for (n=0; n < numModes; n++) {
        CGDisplayModeRef cRef = (CGDisplayModeRef) CFArrayGetValueAtIndex(allModes, n);
        if (cRef != NULL) {
            jobject oneMode = createJavaDisplayMode(cRef, env, displayID);
            (*env)->SetObjectArrayElement(env, jreturnArray, n, oneMode);
            if ((*env)->ExceptionOccurred(env)) {
                (*env)->ExceptionDescribe(env);
                (*env)->ExceptionClear(env);
                continue;
            }
            (*env)->DeleteLocalRef(env, oneMode);
        }
    }
    CFRelease(allModes);
    JNF_COCOA_EXIT(env);

    return jreturnArray;
}

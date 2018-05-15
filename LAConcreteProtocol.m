//
//  EXTConcreteProtocol.m
//  extobjc
//
//  Created by Justin Spahr-Summers on 2010-11-10.
//  Copyright (C) 2012 Justin Spahr-Summers.
//  Released under the MIT license.
//

#import "LAConcreteProtocol.h"
#import "LARuntimeExtensions.h"
#import <pthread.h>
#import <stdlib.h>

/// 自定义类 判断类是否在沙盒， 在沙盒为自定义类 和静态类库里的类， 否则为系统类
static bool la_isInjectBlackList(Class class) {
    return [NSBundle bundleForClass:class] == [NSBundle mainBundle];
}

static CFMutableDictionaryRef inject_alternative_sel_dictionay;
void la_setInjectAlternativeSEL(NSString *class, SEL alternativeSEL, SEL origSEL) {
    if (!inject_alternative_sel_dictionay) {
        inject_alternative_sel_dictionay = CFDictionaryCreateMutable(CFAllocatorGetDefault(),
                                                                 0,
                                                                 &kCFTypeDictionaryKeyCallBacks,
                                                                 &kCFTypeDictionaryValueCallBacks);
    }
    
    CFMutableDictionaryRef classDict = (CFMutableDictionaryRef)CFDictionaryGetValue(inject_alternative_sel_dictionay, (void *)class);
    if (!classDict) {
        classDict = CFDictionaryCreateMutable(CFAllocatorGetDefault(),
                                              0,
                                              &kCFTypeDictionaryKeyCallBacks,
                                              &kCFTypeDictionaryValueCallBacks);
        CFDictionarySetValue(inject_alternative_sel_dictionay, (void *)class, (void *)classDict);
    }
    
    CFDictionarySetValue(classDict, (void *)NSStringFromSelector(alternativeSEL), (void *)[NSValue valueWithPointer:origSEL]);
}

SEL la_injectAlternativeSEL(NSString *class, SEL alternativeSEL) {
    SEL origSEL = NULL;
    if (!inject_alternative_sel_dictionay) return origSEL;

    CFMutableDictionaryRef classDict = (CFMutableDictionaryRef)CFDictionaryGetValue(inject_alternative_sel_dictionay, (void *)class);
    if (classDict) {
        origSEL = [(NSValue *)CFDictionaryGetValue(classDict, (void *)NSStringFromSelector(alternativeSEL)) pointerValue];
    }
    
    return origSEL;
}

static CFMutableDictionaryRef inject_update_only_dictionay;
void la_setInjectUpdateOnly(NSString *class, SEL selector, BOOL isUpdateOnly) {
    if (!inject_update_only_dictionay) {
        inject_update_only_dictionay = CFDictionaryCreateMutable(CFAllocatorGetDefault(),
                                                                 0,
                                                                 &kCFTypeDictionaryKeyCallBacks,
                                                                 &kCFTypeDictionaryValueCallBacks);
    }
    
    CFMutableDictionaryRef classDict = (CFMutableDictionaryRef)CFDictionaryGetValue(inject_update_only_dictionay, (void *)class);
    if (!classDict) {
        classDict = CFDictionaryCreateMutable(CFAllocatorGetDefault(),
                                              0,
                                              &kCFTypeDictionaryKeyCallBacks,
                                              &kCFTypeDictionaryValueCallBacks);
        CFDictionarySetValue(inject_update_only_dictionay, (void *)class, (void *)classDict);
    }
    
    CFDictionarySetValue(classDict, (void *)NSStringFromSelector(selector), (void *)@(isUpdateOnly));
}

BOOL la_injectUpdateOnly(NSString *class, SEL selector) {
    BOOL isUpdateOnly = false;
    if (!inject_update_only_dictionay) return isUpdateOnly;
    
    CFMutableDictionaryRef classDict = (CFMutableDictionaryRef)CFDictionaryGetValue(inject_update_only_dictionay, (void *)class);
    if (classDict) {
        isUpdateOnly = [(NSNumber *)CFDictionaryGetValue(classDict, (void *)NSStringFromSelector(selector)) boolValue];
    }
    
    return isUpdateOnly;
}


static CFMutableDictionaryRef inject_original_imp_dictionay;
void la_setInjectOriginalIMP(Class class, SEL selector, IMP imp) {
    if (!inject_original_imp_dictionay) {
        inject_original_imp_dictionay = CFDictionaryCreateMutable(CFAllocatorGetDefault(),
                                                                  0,
                                                                  &kCFTypeDictionaryKeyCallBacks,
                                                                  &kCFTypeDictionaryValueCallBacks);
    }
    
    CFMutableDictionaryRef classDict = (CFMutableDictionaryRef)CFDictionaryGetValue(inject_original_imp_dictionay, (void *)class);
    if (!classDict) {
        classDict = CFDictionaryCreateMutable(CFAllocatorGetDefault(),
                                              0,
                                              &kCFTypeDictionaryKeyCallBacks,
                                              &kCFTypeDictionaryValueCallBacks);
        CFDictionarySetValue(inject_original_imp_dictionay, (void *)class, (void *)classDict);
    }
    
    CFDictionarySetValue(classDict, (void *)NSStringFromSelector(selector), (void *)[NSValue valueWithPointer:imp]);
}

IMP  la_injectOriginalIMP(Class class, SEL selector) {
    IMP imp = NULL;
    if (!inject_original_imp_dictionay) return imp;
    
    Class klass = class;
    do {
        CFMutableDictionaryRef classDict = (CFMutableDictionaryRef)CFDictionaryGetValue(inject_original_imp_dictionay, (void *)klass);
        if (classDict) {
            imp = [(NSValue *)CFDictionaryGetValue(classDict, (void *)NSStringFromSelector(selector)) pointerValue];
        }
    } while ((klass = class_getSuperclass(klass)) && !imp);
    return imp;
}


static void la_injectConcreteProtocol (Protocol *protocol, Class containerClass, Class class) {
    // get the full list of instance methods implemented by the concrete
    // protocol
    @try{
        
        unsigned imethodCount = 0;
        Method *imethodList = class_copyMethodList(containerClass, &imethodCount);
        
        // get the full list of class methods implemented by the concrete
        // protocolmemcpy
        unsigned cmethodCount = 0;
        Method *cmethodList = class_copyMethodList(object_getClass(containerClass), &cmethodCount);
        
        // get the metaclass of this class (the object on which class
        // methods are implemented)
        Class metaclass = object_getClass(class);
        
        
        // inject all instance methods in the concrete protocol
        for (unsigned methodIndex = 0;methodIndex < imethodCount;++methodIndex) {
            Method method = imethodList[methodIndex];
            SEL selector = method_getName(method);
            
            // first, check to see if such an instance method already exists
            // (on this class or on a superclass)
            
            bool isInstanceMethod = class_getInstanceMethod(class, selector);
            
            if (isInstanceMethod) {
                // it does exist, so don't overwrite it
                IMP old = method_setImplementation(class_getInstanceMethod(class, selector), method_getImplementation(method));//修改现有实现
                la_setInjectOriginalIMP(class, selector, old);
                continue;
            }
            
            if (la_injectUpdateOnly(NSStringFromClass(containerClass), selector)) {
                // 如果只允许更新不允许添加
                SEL orgiSEL = la_injectAlternativeSEL(NSStringFromClass(containerClass), selector);
                if (!(orgiSEL && class_getInstanceMethod(class, orgiSEL))) {
                    // 不进行添加了
                    continue;
                }
            }
            
//            // 向上寻找父类
//            Class clazz = class;
//            bool isSuperInstanceMethod = false;
//            while (!isSuperInstanceMethod && (clazz = class_getSuperclass(clazz))) {
//                isSuperInstanceMethod = class_conformsToProtocol(clazz, protocol);
//                if (isSuperInstanceMethod) {
//                    la_setInjectOriginalIMP(class, selector, );
//                }
//            }

            // add this instance method to the class in question
            IMP imp = method_getImplementation(method);
            const char *types = method_getTypeEncoding(method);
            if (!class_addMethod(class, selector, imp, types)) {
                fprintf(stderr, "ERROR: Could not implement instance method -%s from concrete protocol %s on class %s\n",
                        sel_getName(selector), protocol_getName(protocol), class_getName(class));
            }
        }
        
        // inject all class methods in the concrete protocol
        for (unsigned methodIndex = 0;methodIndex < cmethodCount;++methodIndex) {
            Method method = cmethodList[methodIndex];
            SEL selector = method_getName(method);
            
            // +initialize is a special case that should never be copied
            // into a class, as it performs initialization for the concrete
            // protocol
            if (selector == @selector(initialize)) {
                // so just continue looking through the rest of the methods
                continue;
            }
            
            // first, check to see if a class method already exists (on this
            // class or on a superclass)
            //
            // since 'class' is considered to be an instance of 'metaclass',
            // this is actually checking for class methods (despite the
            // function name)
            if (class_getInstanceMethod(metaclass, selector)) {
                // it does exist, so don't overwrite it
                continue;
            }
            
            // add this class method to the metaclass in question
            IMP imp = method_getImplementation(method);
            const char *types = method_getTypeEncoding(method);
            if (!class_addMethod(metaclass, selector, imp, types)) {
                fprintf(stderr, "ERROR: Could not implement class method +%s from concrete protocol %s on class %s\n",
                        sel_getName(selector), protocol_getName(protocol), class_getName(class));
            }
        }
        
        // free the instance method list
        free(imethodList); imethodList = NULL;
        
        // free the class method list
        free(cmethodList); cmethodList = NULL;
        
        // use [containerClass class] and discard the result to call +initialize
        // on containerClass if it hasn't been called yet
        //
        // this is to allow the concrete protocol to perform custom initialization
        (void)[containerClass class];
        
    } @catch (NSException * e)  {
        
    }
    
}

BOOL la_addConcreteProtocol (Protocol *protocol, Class containerClass) {
    return la_loadSpecialProtocol(protocol, ^(Class destinationClass){
        if (la_isInjectBlackList(destinationClass) && containerClass != destinationClass ) {
            la_injectConcreteProtocol(protocol, containerClass, destinationClass);
        }
    });
}

//extern uint64_t dispatch_benchmark(size_t count, void (^block)(void));
void la_loadConcreteProtocol (Protocol *protocol) {
    
//    uint64_t t = dispatch_benchmark(1, ^{
    la_specialProtocolReadyForInjection(protocol);
//    });
//    NSLog(@"%s 代理的执行速度 : %llu 毫秒", protocol_getName(protocol), t / 1000000);
}


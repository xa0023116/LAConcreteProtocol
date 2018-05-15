//
//  EXTConcreteProtocol.h
//  extobjc
//
//  Created by Justin Spahr-Summers on 2010-11-09.
//  Copyright (C) 2012 Justin Spahr-Summers.
//  Released under the MIT license.
//

#import <objc/runtime.h>
#import <stdio.h>
#import "LAMetamacros.h"
#import <Foundation/Foundation.h>

/**
 * Used to list methods with concrete implementations within a \@protocol
 * definition.
 *
 * Semantically, this is equivalent to using \@optional, but is recommended for
 * documentation reasons. Although concrete protocol methods are optional in the
 * sense that conforming objects don't need to implement them, they are,
 * however, always guaranteed to be present.
 */
#define concrete \
    optional

/**
 * Defines a "concrete protocol," which can provide default implementations of
 * methods within protocol \a NAME. A \@protocol block should exist in a header
 * file, and a corresponding \@concreteprotocol block in an implementation file.
 * Any object that declares itself to conform to protocol \a NAME will receive
 * its method implementations \e only if no method by the same name already
 * exists.
 *
 * @code

// MyProtocol.h
@protocol MyProtocol
@required
- (void)someRequiredMethod;

@optional
- (void)someOptionalMethod;

@concrete
- (BOOL)isConcrete;

@end

// MyProtocol.m
@concreteprotocol(MyProtocol)

- (BOOL)isConcrete {
    return YES;
}

// this will not actually get added to conforming classes, since they are
// required to have their own implementation
- (void)someRequiredMethod {}

@end

 * @endcode
 *
 * If a concrete protocol \c X conforms to another concrete protocol \c Y, any
 * concrete implementations in \c X will be prioritized over those in \c Y. In
 * other words, if both protocols provide a default implementation for a method,
 * the one from \c X (the most descendant) is the one that will be loaded into
 * any class that conforms to \c X. Classes that conform to \c Y will naturally
 * only use the implementations from \c Y.
 *
 * To perform tasks when a concrete protocol is loaded, use the \c +initialize
 * method. This method in a concrete protocol is treated similarly to \c +load
 * in categories – it will be executed at most once per concrete protocol, and
 * is not added to any classes which receive the concrete protocol's methods.
 * The protocol's methods will have been added to all conforming classes at the
 * time that \c +initialize is invoked. If no class conforms to the concrete
 * protocol, \c +initialize may never be called.
 *
 * @note You cannot define instance variables in a concrete protocol.
 *
 * @warning You should not invoke methods against \c super in the implementation
 * of a concrete protocol, as the superclass may not be the type you expect (and
 * may not even inherit from \c NSObject).
 */

#define la_concrete_protocol(NAME) \
    /*
     * create a class used to contain all the methods used in this protocol
     */ \
interface LA_ ## NAME ## _ProtocolMethodContainer : NSObject < NAME > {} \
    @end \
    \
    @implementation LA_ ## NAME ## _ProtocolMethodContainer \
    /*
     * when this class is loaded into the runtime, add the concrete protocol
     * into the list we have of them
     */ \
    + (void)load { \
        /*
         * passes the actual protocol as the first parameter, then this class as
         * the second
         */ \
        if (!la_addConcreteProtocol(objc_getProtocol(metamacro_stringify(NAME)), self)) \
            fprintf(stderr, "ERROR: Could not load concrete protocol %s\n", metamacro_stringify(NAME)); \
    } \
    \
    /*
     * using the "constructor" function attribute, we can ensure that this
     * function is executed only AFTER all the Objective-C runtime setup (i.e.,
     * after all +load methods have been executed)
     */ \
    __attribute__((constructor)) \
    static void la_ ## NAME ## _inject (void) { \
        /*
         * use this injection point to mark this concrete protocol as ready for
         * loading
         */ \
        la_loadConcreteProtocol(objc_getProtocol(metamacro_stringify(NAME))); \
        if (strcmp(metamacro_stringify(NAME),"UITableViewDelegate") == 0) {    \
            la_setInjectAlternativeSEL(@"LA_UITableViewDelegate_ProtocolMethodContainer", @selector(tableView:willDisplayFooterView:forSection:), @selector(tableView:viewForFooterInSection:)); \
            la_setInjectAlternativeSEL(@"LA_UITableViewDelegate_ProtocolMethodContainer", @selector(tableView:willDisplayHeaderView:forSection:), @selector(tableView:viewForHeaderInSection:)); \
            la_setInjectUpdateOnly(@"LA_UITableViewDelegate_ProtocolMethodContainer",@selector(tableView:willDisplayHeaderView:forSection:), true); \
            la_setInjectUpdateOnly(@"LA_UITableViewDelegate_ProtocolMethodContainer",@selector(tableView:willDisplayFooterView:forSection:), true); \
        } else if (strcmp(metamacro_stringify(NAME),"UICollectionViewDelegate") == 0) { \
            la_setInjectAlternativeSEL(@"LA_UICollectionViewDelegate_ProtocolMethodContainer", @selector(collectionView:willDisplaySupplementaryView:forElementKind:atIndexPath:), @selector(collectionView:viewForSupplementaryElementOfKind:atIndexPath:)); \
            la_setInjectUpdateOnly(@"LA_UICollectionViewDelegate_ProtocolMethodContainer",@selector(collectionView:willDisplaySupplementaryView:forElementKind:atIndexPath:), true); \
        } \
    }


/*** implementation details follow ***/
BOOL la_addConcreteProtocol (Protocol *protocol, Class methodContainer);
void la_loadConcreteProtocol (Protocol *protocol);
IMP  la_InjectSuperInstanceMethod(NSString *class, SEL selector);
IMP  la_injectOriginalIMP(Class class, SEL selector);
void la_setInjectUpdateOnly(NSString *class, SEL selector, BOOL isUpdateOnly);
void la_setInjectAlternativeSEL(NSString *class, SEL alternativeSEL, SEL origSEL);

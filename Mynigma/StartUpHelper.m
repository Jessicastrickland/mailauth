//
//	Copyright © 2012 - 2015 Roman Priebe
//
//	This file is part of M - Safe email made simple.
//
//	M is free software: you can redistribute it and/or modify
//	it under the terms of the GNU General Public License as published by
//	the Free Software Foundation, either version 3 of the License, or
//	(at your option) any later version.
//
//	M is distributed in the hope that it will be useful,
//	but WITHOUT ANY WARRANTY; without even the implied warranty of
//	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//	GNU General Public License for more details.
//
//	You should have received a copy of the GNU General Public License
//	along with M.  If not, see <http://www.gnu.org/licenses/>.
//





#import "StartUpHelper.h"
#import "AppDelegate.h"
#import "UserSettings+Category.h"
#import "NSString+EmailAddresses.h"
#import "EmailMessageController.h"
#import "IMAPAccountSetting+Category.h"
#import <AddressBook/AddressBook.h>
#import "AlertHelper.h"
#import "AccountCreationManager.h"
#import "ABContactDetail+Category.h"
#import "EmailMessage+Category.h"
#import "EmailContactDetail+Category.h"
#import "MynigmaPublicKey+Category.h"
#import "UIDHelper.h"
#import "IMAPAccount.h"
#import "AccountCheckManager.h"
#import "Contact+Category.h"
#import "EmailMessageInstance.h"
#import "EmailMessageData.h"
#import "EmailMessage.h"
#import "Recipient.h"
#import "AddressDataHelper.h"
#include <CommonCrypto/CommonDigest.h>
#import "SelectionAndFilterHelper.h"
#import "EmailMessageInstance+Category.h"
#if ULTIMATE

#import "ServerHelper.h"

#endif



#if TARGET_OS_IPHONE

#import "ContactSuggestions.h"
#import "ViewControllersManager.h"
#import "SplitViewController.h"

#endif




@implementation StartUpHelper



#pragma mark -
#pragma mark STARTUP TASKS

+ (void)performStartupTasks
{
    //load user settings and list of accounts
    [self loadOrCreateUserSettings];
    
    //load the own entry from the address book
    [self loadOwnContactFromAddressbook];
    
    //load the NSFetchedResultsControllers etc...
    [self loadFromStore];
    
    //collect the allMessages, allEmails, etc. lists
    [self collectAllObjects];
    
    //set unread relationships right
    //[self fixUnreadCount];
    
    //check all accounts
    [self startupCheck];
}


//first load the user's own contact from the address book and collect any email addresses
+ (void)loadOwnContactFromAddressbook
{
    //don't access the address book before accounts are set up
    //that would be a little creepy...
    if([UserSettings usedAccounts].count==0)
    {
        [NSString setUsersAddresses:[NSArray new]];
        return;
    }
    
    //array into which the user's own email addresses will be collected
    NSMutableArray* myEmails = [NSMutableArray new];
    
#if TARGET_OS_IPHONE
    
#else
    
    if(![UserSettings currentUserSettings].haveExplainedContactsAccess.boolValue)
    {
        NSAlert* alert = [NSAlert alertWithMessageText:NSLocalizedString(@"Mynigma can populate its contact list with email addresses and photos from the Contacts app, if you grant permission.", @"") defaultButton:NSLocalizedString(@"OK", @"OK button") alternateButton:nil otherButton:nil informativeTextWithFormat:NSLocalizedString(@"All data will stay on this computer. Nothing will be shared with us or any third party.", @"")];
        
        [alert runModal];
    }
    
    [[UserSettings currentUserSettings] setHaveExplainedContactsAccess:@YES];
    
    ABAddressBook *addressBook;
    addressBook = [ABAddressBook sharedAddressBook];
    
    
    //the user's own entry in the address book
    ABPerson* ego = [addressBook me];
    
    //first go through the emails listed in the address book entry
    if(ego)
    {
        ABMultiValue* emails = [ego valueForProperty:kABEmailProperty];
        for(NSUInteger index = 0;index<[emails count];index++)
        {
            NSString* emailAddress = [[emails valueAtIndex:index] lowercaseString];
            [myEmails addObject:emailAddress];
        }
    }
    
    
#endif
    
    
    //now go through the user's sender addresses associated with each account setting in the store
    for(IMAPAccountSetting* accountSetting in [UserSettings currentUserSettings].accounts)
    {
        NSString* canonicalEmail = accountSetting.emailAddress.canonicalForm;
        if(canonicalEmail)
        {
            if(![myEmails containsObject:canonicalEmail])
                [myEmails addObject:canonicalEmail];
        }
        else NSLog(@"No email address set for account!!");
    }
    
    [NSString setUsersAddresses:myEmails];
}

+ (void)loadFromStore
{
    
    
    [EmailMessageController sharedInstance].messageInstanceSortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"message.dateSent" ascending:NO], [NSSortDescriptor sortDescriptorWithKey:@"message.messageid" ascending:NO], [NSSortDescriptor sortDescriptorWithKey:@"uid" ascending:NO]];
    
    //[EmailMessageController sharedInstance].messageInstanceSortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"message.messageData.subject" ascending:YES],[NSSortDescriptor sortDescriptorWithKey:@"message.dateSent" ascending:NO], [NSSortDescriptor sortDescriptorWithKey:@"message.messageid" ascending:NO], [NSSortDescriptor sortDescriptorWithKey:@"uid" ascending:NO]];
    
    [EmailMessageController sharedInstance].messageSortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"dateSent" ascending:NO], [NSSortDescriptor sortDescriptorWithKey:@"messageid" ascending:NO]];
    
#if TARGET_OS_IPHONE
    
    NSFetchRequest* fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"Contact"];
    if(ABPersonGetSortOrdering()==kABPersonSortByFirstName)
        [fetchRequest setSortDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"dateLastContacted" ascending:NO],[NSSortDescriptor sortDescriptorWithKey:@"addressBookContact.firstName" ascending:YES],[NSSortDescriptor sortDescriptorWithKey:@"addressBookContact.lastName" ascending:YES],[NSSortDescriptor sortDescriptorWithKey:@"addressBookContact.uid" ascending:YES]]];
    else
        [fetchRequest setSortDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"dateLastContacted" ascending:NO],          [NSSortDescriptor sortDescriptorWithKey:@"addressBookContact.lastName" ascending:YES],[NSSortDescriptor sortDescriptorWithKey:@"addressBookContact.firstName" ascending:YES],[NSSortDescriptor sortDescriptorWithKey:@"addressBookContact.uid" ascending:YES]]];
    
    [fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"(dateLastContacted != NULL) AND (NONE emailAddresses.address IN %@)", [NSString usersAddresses]]];
    APPDELEGATE.recentContacts = [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest managedObjectContext:MAIN_CONTEXT sectionNameKeyPath:nil cacheName:@"RecentContacts"];
    //[APPDELEGATE.recentContacts setDelegate:contactsController];
    NSError* error = nil;
    [APPDELEGATE.recentContacts performFetch:&error];
    if(error)
        NSLog(@"Error fetching recent contacts: %@",error);
    
    NSFetchRequest* contactFetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"Contact"];
    if(ABPersonGetSortOrdering()==kABPersonSortByFirstName)
        [contactFetchRequest setSortDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"addressBookContact.firstName" ascending:YES],[NSSortDescriptor sortDescriptorWithKey:@"addressBookContact.lastName" ascending:YES],[NSSortDescriptor sortDescriptorWithKey:@"addressBookContact.uid" ascending:YES]]];
    else
        [contactFetchRequest setSortDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"addressBookContact.lastName" ascending:YES],[NSSortDescriptor sortDescriptorWithKey:@"addressBookContact.firstName" ascending:YES],[NSSortDescriptor sortDescriptorWithKey:@"addressBookContact.uid" ascending:YES]]];
    
    APPDELEGATE.contacts = [[NSFetchedResultsController alloc] initWithFetchRequest:contactFetchRequest managedObjectContext:MAIN_CONTEXT sectionNameKeyPath:nil cacheName:@"Contacts"];
    error = nil;
    
    [APPDELEGATE.contacts setDelegate:APPDELEGATE.contactSuggestions];
    [APPDELEGATE.contacts performFetch:&error];
    if(error)
        NSLog(@"Error fetching contacts: %@",error);
    
    [APPDELEGATE.contactSuggestions initialFetchDone];
    
    NSFetchRequest* newFetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"EmailMessageInstance"];
    [newFetchRequest setSortDescriptors:[EmailMessageController sharedInstance].messageInstanceSortDescriptors];
    [newFetchRequest setPredicate:[NSPredicate predicateWithValue:YES]];
    //[newFetchRequest setFetchLimit:100];
    //[newFetchRequest setFetchBatchSize:20];
//message.messageData.subject
    
    APPDELEGATE.messages = [[NSFetchedResultsController alloc] initWithFetchRequest:newFetchRequest managedObjectContext:MAIN_CONTEXT sectionNameKeyPath:nil cacheName:nil];
    //APPDELEGATE.messages = [[NSFetchedResultsController alloc] initWithFetchRequest:newFetchRequest managedObjectContext:MAIN_CONTEXT sectionNameKeyPath:@"message.messageData.subject" cacheName:nil];
    [APPDELEGATE.messages setDelegate:[EmailMessageController sharedInstance]];
    
    error = nil;
    [APPDELEGATE.messages performFetch:&error];
       //NSMutableArray *groupMessages = [[APPDELEGATE.messages.fetchedObjects mutableCopy];
    
    [ThreadHelper ensureMainThread];
    NSMutableArray* messageInstanceObjectIDs = [NSMutableArray new];
    
    for(EmailMessageInstance* messageInstance in APPDELEGATE.messages.fetchedObjects)
    {
        if(![messageInstance.message isDeviceMessage])
            [messageInstanceObjectIDs addObject:messageInstance.objectID];
    }
    
   
    [ThreadHelper runAsyncFreshLocalChildContext:^(NSManagedObjectContext *localContext) {
        
        NSInteger counter = 0;
        
        for(NSManagedObjectID* messageInstanceObjectID in messageInstanceObjectIDs)
        {
            EmailMessageInstance* messageInstance = [EmailMessageInstance messageInstanceWithObjectID:messageInstanceObjectID inContext:localContext];
            
            counter++;
            Recipient *fromRecipient = [AddressDataHelper senderAsRecipientForMessage:[messageInstance message]] ;
            NSString  *hash =[self sha256:[fromRecipient displayEmail]];
            NSError *error;
            NSString *url_string = [NSString stringWithFormat: @"http://api.authenticatedreality.com/emails/check?hash=" ];
            url_string= [url_string stringByAppendingString:hash];
            NSData *data = [NSData dataWithContentsOfURL: [NSURL URLWithString:url_string]];
            NSMutableArray *json = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&error];
            
            NSNumber  *authenticated = [json valueForKey: hash];
            //NSLog(@"From: %@ -> authenticated : %@",[fromRecipient displayEmail],authenticated);

            [[messageInstance message] setValue:authenticated forKey:@"authenticated"];
            [localContext save:nil];
            
            [CoreDataHelper saveWithCallback:^{
                
#if TARGET_OS_IPHONE
                
                [[EmailMessageController sharedInstance] updateFiltersReselectingIndexPath:nil];
                
#endif
                
            }];
        }
        
        [localContext save:nil];
        
        [CoreDataHelper saveWithCallback:^{
            
#if TARGET_OS_IPHONE
            
            [[EmailMessageController sharedInstance] updateFiltersReselectingIndexPath:nil];
            
#endif
            
        }];
        
    }];
    // end add by ddo
    
    NSMutableArray *groupMessages = [[NSMutableArray alloc]init];
    groupMessages = [NSMutableArray arrayWithArray:APPDELEGATE.messages.fetchedObjects];


    NSInteger count = 0;
    while (count < [groupMessages count]){
        EmailMessageInstance* messageObject = [groupMessages objectAtIndex: count];
        //NSLog(@"%@ | %@", [[messageObject message] messageid],[[[messageObject message] messageData] subject]);
        NSMutableArray *references = [NSKeyedUnarchiver unarchiveObjectWithData:[messageObject message].references];
        if (references !=nil){
        for (NSString *ref in references){
            NSMutableIndexSet *indexesToDelete = [NSMutableIndexSet indexSet];
            NSUInteger currentIndex = 0;
            for (EmailMessageInstance* refObject in groupMessages){
                if ([[[refObject message] messageid] isEqualToString:ref] ){
                    [indexesToDelete addIndex:currentIndex];
                }
                currentIndex++;
            }
            NSLog(@"%@",indexesToDelete);
            [groupMessages removeObjectsAtIndexes:indexesToDelete];
        }
        }
        //NSLog(@"The content of references array is%@",references);
        count++;
    }

    //APPDELEGATE.displayedGroupMessages = groupMessages;

    APPDELEGATE.displayedMessages = APPDELEGATE.messages.fetchedObjects;
    APPDELEGATE.displayedGroupMessages = groupMessages;
   // NSLog(@"The content of arry is%@",APPDELEGATE.displayedMessages);
    [[EmailMessageController sharedInstance] initialFetchDone];
    
    NSLog(@"%@ %lu messages, error: %@", [EmailMessageController sharedInstance], (unsigned long)APPDELEGATE.messages.fetchedObjects.count, error.localizedDescription);
    
#else
    
    APPDELEGATE.recentContacts = [NSArrayController new];
    [APPDELEGATE.recentContacts setManagedObjectContext:MAIN_CONTEXT];
    [APPDELEGATE.recentContacts setEntityName:@"Contact"];
    [APPDELEGATE.recentContacts setSortDescriptors:[NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"dateLastContacted" ascending:NO]]];
    [APPDELEGATE.recentContacts setFetchPredicate:[NSPredicate predicateWithFormat:@"(dateLastContacted != NULL) AND (NONE emailAddresses.address IN %@)", [NSString usersAddresses]]];
    
    [APPDELEGATE.recentContacts fetch:self];
    [APPDELEGATE.recentContacts setAvoidsEmptySelection:NO];
    [APPDELEGATE.recentContacts setAutomaticallyPreparesContent:YES];
    [APPDELEGATE.recentContacts setAutomaticallyRearrangesObjects:YES];
    [APPDELEGATE.recentContacts setClearsFilterPredicateOnInsertion:NO];
    
    
    [APPDELEGATE.messages setManagedObjectContext:MAIN_CONTEXT];
    [APPDELEGATE.messages setEntityName:@"EmailMessageInstance"];
    [APPDELEGATE.messages setAvoidsEmptySelection:NO];
    
    
    [APPDELEGATE.messages fetch:self];
    
    
    APPDELEGATE.contacts = [NSArrayController new];
    [APPDELEGATE.contacts setManagedObjectContext:MAIN_CONTEXT];
    [APPDELEGATE.contacts setEntityName:@"Contact"];
    [APPDELEGATE.contacts setAvoidsEmptySelection:NO];
    [APPDELEGATE.contacts setClearsFilterPredicateOnInsertion:NO];
    [APPDELEGATE.contacts setSortDescriptors:[NSArray arrayWithObjects:[[NSSortDescriptor alloc] initWithKey:@"self" ascending:YES comparator:^(Contact* obj1, Contact* obj2){
        return [[obj1 displayName] compare:[obj2 displayName]];
    }], nil]];
    
    [APPDELEGATE.contacts fetch:self];
    [APPDELEGATE.contacts setAutomaticallyPreparesContent:YES];
    [APPDELEGATE.contacts setAutomaticallyRearrangesObjects:YES];
    
    [APPDELEGATE setViewerArray:nil];
    
#endif
    
}



+ (void)loadOrCreateUserSettings
{
    NSFetchRequest* fetchRequest = [[NSFetchRequest alloc] initWithEntityName:@"UserSettings"];
    NSError* error = nil;
    NSArray* settingsArray = [MAIN_CONTEXT executeFetchRequest:fetchRequest error:&error];
    if(error || !settingsArray)
        NSLog(@"Error loading settings");
    uid_t uid = getuid();
    NSPredicate* predicate = [NSPredicate predicateWithFormat:@"uid = %d", uid];
    NSArray* filteredArray = [settingsArray filteredArrayUsingPredicate:predicate];
    if(filteredArray.count==0) //no user setting exists, create a new one
    {
        NSEntityDescription* entity = [NSEntityDescription entityForName:@"UserSettings" inManagedObjectContext:MAIN_CONTEXT];
        [UserSettings setCurrentUserSettings:[[UserSettings alloc] initWithEntity:entity insertIntoManagedObjectContext:MAIN_CONTEXT]];
        [[UserSettings currentUserSettings] setUid:[NSNumber numberWithUnsignedInteger:(UInt32)getuid()]];
        
        //do this later - need the split view to be shown before we can animate a transition to the setup screen
        //        [AlertHelper showWelcomeSheet];
        
#if TARGET_OS_IPHONE
        
        [[[ViewControllersManager sharedInstance] splitViewController] showWelcomeScreenWhenLoaded];
        
#else
        
        [AlertHelper showWelcomeSheet];
        
#endif
        
        [CoreDataHelper save];
    }
    else if(filteredArray.count==1) //found an existing user setting
    {
        [UserSettings setCurrentUserSettings:filteredArray.firstObject];
        
        if([UserSettings currentUserSettings].accounts.count==0) //no IMAPAccountSetting present, so show the welcome screen
        {
            
#if TARGET_OS_IPHONE
            
            //do this later - need the split view to be shown before we can animate a transition to the setup screen
            [[[ViewControllersManager sharedInstance] splitViewController] showWelcomeScreenWhenLoaded];
            
#else
            
            [AlertHelper showWelcomeSheet];
            
#endif
            
        }
        else //Found an IMAPAccountSetting: proceed. Additional accounts can be set up in the preferences
        {
            [AccountCreationManager resetIMAPAccountsFromAccountSettings];
        }
    }
    else
        NSLog(@"ERROR: %ld user settings found",(unsigned long)filteredArray.count);
}

+ (void)collectAllObjects
{
    NSLog(@"Started collecting all objects");
    
    //the allContacts dictionary contains the objectIDs of all ABContactDetails, organised by name (both in the "firstName lastName" and the "lastName, firstName" format)
    [ABContactDetail collectAllABContacts];
    
    //the allEmailAddresses dictionary contains the objectIDs of all EmailContactDetails, organised by email address
    [EmailContactDetail collectAllContactDetails];
    
    //
    [EmailMessage collectAllMessagesWithCallback:nil];
    
    [MynigmaPublicKey compilePublicKeyIndex];
    
    [UIDHelper compileUIDinFolderIndex];
}

//request any new public keys from the server and check the accounts for the first time
+ (void)startupCheck
{
    for(IMAPAccountSetting* accountSetting in [UserSettings currentUserSettings].accounts)
    {
        if([accountSetting isKindOfClass:[IMAPAccountSetting class]])
        {
            [MAIN_CONTEXT performBlock:^{
                
#if ULTIMATE
                if([accountSetting hasBeenVerified].boolValue)
                    [SERVER sendNewContactsToServerWithAccount:accountSetting withCallback:nil];
#endif
                [AccountCheckManager startupCheckForAccountSetting:accountSetting];
            }];
            
        }
    }
}

//add by ddo
+ (NSString*) sha256:(NSString *)clear{
    const char *s=[clear cStringUsingEncoding:NSASCIIStringEncoding];
    NSData *keyData=[NSData dataWithBytes:s length:strlen(s)];
    
    uint8_t digest[CC_SHA256_DIGEST_LENGTH]={0};
    CC_SHA256(keyData.bytes, keyData.length, digest);
    NSData *out=[NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
    NSString *hash=[out description];
    hash = [hash stringByReplacingOccurrencesOfString:@" " withString:@""];
    hash = [hash stringByReplacingOccurrencesOfString:@"<" withString:@""];
    hash = [hash stringByReplacingOccurrencesOfString:@">" withString:@""];
    return hash;
}


@end

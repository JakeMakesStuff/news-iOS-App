//
//  NewsSessionManager.swift
//  CloudNews
//
//  Created by Peter Hedlund on 10/20/18.
//  Copyright © 2018 Peter Hedlund. All rights reserved.
//

import Cocoa
import Alamofire

typealias SyncCompletionBlock = () -> Void
typealias SyncCompletionBlockNewItems = (_ newItems: [ItemProtocol]) -> Void

class NewsSessionManager: Alamofire.SessionManager {

    static let shared = NewsSessionManager()
    
    init() {
        let configuration = URLSessionConfiguration.background(withIdentifier: "com.peterandlinda.CloudNews.background")
        super.init(configuration: configuration)
    }
    
}


class NewsManager {
    
    static let shared = NewsManager()
    
    var syncTimer: Timer?
    
    init() {
        self.setupSyncTimer()
    }
    
    func setupSyncTimer() {
        self.syncTimer?.invalidate()
        self.syncTimer = nil
        let interval = UserDefaults.standard.integer(forKey: "interval")
        if interval > 0 {
            var timeInterval: TimeInterval = 900
            switch interval {
            case 2: timeInterval = 30 * 60
            case 3: timeInterval = 60 * 60
            default: timeInterval = 15 * 60
            }
            self.syncTimer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: true) { (_) in
                NotificationCenter.default.post(name: NSNotification.Name("SyncInitiated"), object: nil)
                self.sync(completion: {
                    NotificationCenter.default.post(name: NSNotification.Name("SyncComplete"), object: nil)
                })
            }
        }
    }

    func addFeed(url: String) {
        let router = Router.createFeed(url: url, folder: 0)
        
        NewsSessionManager.shared.request(router).responseDecodable(completionHandler: { (response: DataResponse<Feeds>) in
            debugPrint(response)
        })
    }
    
    func addFolder(name: String) {
        let router = Router.createFolder(name: name)
        
        NewsSessionManager.shared.request(router).responseDecodable(completionHandler: { (response: DataResponse<Folders>) in
            debugPrint(response)
        })
    }

    func markRead(itemIds: [Int32], state: Bool, completion: @escaping SyncCompletionBlock) {
        CDItem.markRead(itemIds: itemIds, state: state) {
            completion()
            let parameters: Parameters = ["items": itemIds]
            var router: Router
            if state {
                router = Router.itemsUnread(parameters: parameters)
            } else {
                router = Router.itemsRead(parameters: parameters)
            }
            NewsSessionManager.shared.request(router).responseData { response in
                switch response.result {
                case .success:
                    if state {
                        CDUnread.deleteItemIds(itemIds: itemIds, in: NewsData.mainThreadContext)
                    } else {
                        CDRead.deleteItemIds(itemIds: itemIds, in: NewsData.mainThreadContext)
                    }
                default:
                    break
                }
            }
        }
    }

    func markStarred(item: CDItem, starred: Bool, completion: @escaping SyncCompletionBlock) {
        CDItem.markStarred(itemId: item.id, state: starred) {
            completion()
            let parameters: Parameters = ["items": [["feedId": item.feedId,
                                                     "guidHash": item.guidHash as Any]]]
            var router: Router
            if starred {
                router = Router.itemsStarred(parameters: parameters)
            } else {
                router = Router.itemsUnstarred(parameters: parameters)
            }
            NewsSessionManager.shared.request(router).responseData { response in
                switch response.result {
                case .success:
                    if starred {
                        CDStarred.deleteItemIds(itemIds: [item.id], in: NewsData.mainThreadContext)
                    } else {
                        CDUnstarred.deleteItemIds(itemIds: [item.id], in: NewsData.mainThreadContext)
                    }
                default:
                    break
                }
                completion()
            }
        }
    }

    /*
     Initial sync
     
     1. unread articles: GET /items?type=3&getRead=false&batchSize=-1
     2. starred articles: GET /items?type=2&getRead=true&batchSize=-1
     3. folders: GET /folders
     4. feeds: GET /feeds
     */
    
    func initialSync() {
        
        // 1.
        let unreadParameters: Parameters = ["type": 3,
                                            "getRead": false,
                                            "batchSize": -1]
        
        let unreadItemRouter = Router.items(parameters: unreadParameters)
        NewsSessionManager.shared.request(unreadItemRouter).responseDecodable(completionHandler: { (response: DataResponse<Items>) in
//            debugPrint(response)
            if let items = response.value?.items {
                CDItem.update(items: items, completion: nil)
                self.updateBadge()
            }
        })

        // 2.
        let starredParameters: Parameters = ["type": 2,
                                             "getRead": true,
                                             "batchSize": -1]
        
        let starredItemRouter = Router.items(parameters: starredParameters)
        NewsSessionManager.shared.request(starredItemRouter).responseDecodable(completionHandler: { (response: DataResponse<Items>) in
//            debugPrint(response)
            if let items = response.value?.items {
                CDItem.update(items: items, completion: nil)
                self.updateBadge()
            }
        })

        // 3.
        NewsSessionManager.shared.request(Router.folders).responseDecodable(completionHandler: { (response: DataResponse<Folders>) in
//            debugPrint(response)
            if let folders = response.value?.folders {
                CDFolder.update(folders: folders)
            }
        })

        // 4.
        NewsSessionManager.shared.request(Router.feeds).responseDecodable(completionHandler: { (response: DataResponse<Feeds>) in
//            debugPrint(response)
            if let newestItemId = response.value?.newestItemId, let starredCount = response.value?.starredCount {
                CDFeeds.update(starredCount: starredCount, newestItemId: newestItemId)
            }
            if let feeds = response.value?.feeds {
                CDFeed.update(feeds: feeds)
            }
        })
    }
    
    
    /*
     Syncing
     
     When syncing, you want to push read/unread and starred/unstarred items to the server and receive new and updated items, feeds and folders. To do that, call the following routes:
     
     1. Notify the News app of unread articles: PUT /items/unread/multiple {"items": [1, 3, 5] }
     2. Notify the News app of read articles: PUT /items/read/multiple {"items": [1, 3, 5]}
     3. Notify the News app of starred articles: PUT /items/starred/multiple {"items": [{"feedId": 3, "guidHash": "adadafasdasd1231"}, ...]}
     4. Notify the News app of unstarred articles: PUT /items/unstarred/multiple {"items": [{"feedId": 3, "guidHash": "adadafasdasd1231"}, ...]}
     5. Get new folders: GET /folders
     6. Get new feeds: GET /feeds
     7. Get new items and modified items: GET /items/updated?lastModified=12123123123&type=3

     */
    func sync(completion: @escaping SyncCompletionBlock) {
        guard let _ = CDItem.all() else {
            self.initialSync()
            return
        }

        //2
        func localRead(completion: @escaping SyncCompletionBlock) {
            if let localRead = CDRead.all(), localRead.count > 0 {
                let readParameters: Parameters = ["items": localRead]
                NewsSessionManager.shared.request(Router.itemsRead(parameters: readParameters)).responseData { response in
                    switch response.result {
                    case .success:
                        CDRead.clear()
                    default:
                        break
                    }
                    completion()
                }
            } else {
                completion()
            }
        }
        
        //3
        func localStarred(completion: @escaping SyncCompletionBlock) {
            if let localStarred = CDStarred.all(), localStarred.count > 0 {
                if let starredItems = CDItem.items(itemIds: localStarred) {
                    var params: [Any] = []
                    for starredItem in starredItems {
                        var param: [String: Any] = [:]
                        param["feedId"] = starredItem.feedId
                        param["guidHash"] = starredItem.guidHash
                        params.append(param)
                    }
                    let starredParameters: Parameters = ["items": params]
                    NewsSessionManager.shared.request(Router.itemsStarred(parameters: starredParameters)).responseData { response in
                        switch response.result {
                        case .success:
                            CDStarred.clear()
                        default:
                            break
                        }
                        completion()
                    }
                } else {
                    completion()
                }
            } else {
                completion()
            }
        }

        //4
        func localUnstarred(completion: @escaping SyncCompletionBlock) {
            if let localUnstarred = CDUnstarred.all(), localUnstarred.count > 0 {
                if let unstarredItems = CDItem.items(itemIds: localUnstarred) {
                    var params: [Any] = []
                    for unstarredItem in unstarredItems {
                        var param: [String: Any] = [:]
                        param["feedId"] = unstarredItem.feedId
                        param["guidHash"] = unstarredItem.guidHash
                        params.append(param)
                    }
                    let unstarredParameters: Parameters = ["items": params]
                    NewsSessionManager.shared.request(Router.itemsUnstarred(parameters: unstarredParameters)).responseData { response in
                        switch response.result {
                        case .success:
                            CDUnstarred.clear()
                        default:
                            break
                        }
                        completion()
                    }
                } else {
                    completion()
                }
            } else {
                completion()
            }
        }

        //5
        func folders(completion: @escaping SyncCompletionBlock) {
            NewsSessionManager.shared.request(Router.folders).responseDecodable(completionHandler: { (response: DataResponse<Folders>) in
                //            debugPrint(response)
                if let folders = response.value?.folders {
                    CDFolder.update(folders: folders)
                    let ids = folders.map({ $0.id })
                    if let knownFolders = CDFolder.all() {
                        let knownIds = knownFolders.map({ $0.id })
                        let deletedFolders = knownIds.filter({
                            return !ids.contains($0)
                        })
                        CDFolder.delete(ids: deletedFolders, in: NewsData.mainThreadContext)
                    }
                }
                completion()
            })
        }
        
        //6
        func feeds(completion: @escaping SyncCompletionBlock) {
            NewsSessionManager.shared.request(Router.feeds).responseDecodable(completionHandler: { (response: DataResponse<Feeds>) in
                //            debugPrint(response)
                if let newestItemId = response.value?.newestItemId, let starredCount = response.value?.starredCount {
                    CDFeeds.update(starredCount: starredCount, newestItemId: newestItemId)
                }
                if let feeds = response.value?.feeds {
                    CDFeed.update(feeds: feeds)
                    let ids = feeds.map({ $0.id })
                    if let knownFeeds = CDFeed.all() {
                        let knownIds = knownFeeds.map({ $0.id })
                        let deletedFeeds = knownIds.filter({
                            return !ids.contains($0)
                        })
                        CDFeed.delete(ids: deletedFeeds, in: NewsData.mainThreadContext)
                        if let allItems = CDItem.all() {
                            let deletedFeedItems = allItems.filter({
                                return deletedFeeds.contains($0.feedId)
                            })
                            let deletedFeedItemIds = deletedFeedItems.map({ $0.id })
                            CDItem.delete(ids: deletedFeedItemIds, in: NewsData.mainThreadContext)
                        }
                    }
                }
                completion()
            })
        }
        
        //7
        func items(completion: @escaping SyncCompletionBlock) {
            let updatedParameters: Parameters = ["type": 3,
                                                 "lastModified": CDItem.lastModified(),
                                                 "id": 0]
            
            let updatedItemRouter = Router.updatedItems(parameters: updatedParameters)
            NewsSessionManager.shared.request(updatedItemRouter).responseDecodable(completionHandler: { (response: DataResponse<Items>) in
                //            debugPrint(response)
                if let items = response.value?.items {
                    CDItem.update(items: items, completion: { (newItems) in
                        for newItem in newItems {
                            let feed = CDFeed.feed(id: newItem.feedId)
                            let notification = NSUserNotification()
                            notification.identifier = NSUUID().uuidString
                            notification.title = "CloudNews"
                            notification.subtitle = feed?.title ?? "New article"
                            notification.informativeText = newItem.title ?? ""
                            notification.soundName = NSUserNotificationDefaultSoundName
                            let notificationCenter = NSUserNotificationCenter.default
                            notificationCenter.deliver(notification)
                        }
                    })
                }
                completion()
            })
        }
        
        localRead {
            localStarred {
                localUnstarred {
                    folders {
                        feeds {
                            items {
                                self.updateBadge()
                                completion()
                            }
                        }
                    }
                }
            }
        }
    }

    func updateBadge() {
        let unreadCount = CDItem.unreadCount()
        if unreadCount > 0 {
            NSApp.dockTile.badgeLabel = "\(unreadCount)"
        } else {
            NSApp.dockTile.badgeLabel = nil
        }
    }

}

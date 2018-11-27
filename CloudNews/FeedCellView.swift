//
//  FeedCellView.swift
//  CloudNews
//
//  Created by Peter Hedlund on 11/17/18.
//  Copyright © 2018 Peter Hedlund. All rights reserved.
//

import Cocoa

class FeedCellView: NSTableCellView {
    
    @IBOutlet var faviconImage: NSImageView!
    @IBOutlet var nameLabel: NSTextField!
    @IBOutlet var unreadCountButton: NSButton!
    
    func special(name: String, starred: Bool) {
        self.nameLabel.stringValue = name
        if starred {
            let image = NSImage(named: "Starred Articles")
            self.faviconImage.image = image
            let unreadCount = CDItem.starredItems()?.count
            if let unreadCount = unreadCount {
                if unreadCount > 0 {
                    self.unreadCountButton.title = "\(unreadCount)"
                    self.unreadCountButton.isHidden = false
                } else {
                    self.unreadCountButton.title = ""
                    self.unreadCountButton.isHidden = true
                }
            }            
        } else {
            let image = NSImage(named: "All Articles")
            self.faviconImage.image = image
            let unreadCount = CDItem.unreadCount()
            
            if unreadCount > 0 {
                self.unreadCountButton.title = "\(unreadCount)"
                self.unreadCountButton.isHidden = false
            } else {
                self.unreadCountButton.title = ""
                self.unreadCountButton.isHidden = true
            }
        }
    }
    
    var folder: FolderProtocol? {
        didSet {
            if let folder = self.folder {
                self.nameLabel.stringValue = folder.name ?? ""
                let image = NSImage(named: "folder")
                self.faviconImage.image = image
                let folderFeeds = CDFeed.inFolder(folder: folder.id)
                let unreadCount = folderFeeds?.map { $0.unreadCount }.reduce(0) { $0 + $1 }
                
                if let unreadCount = unreadCount {
                    if unreadCount > 0 {
                        self.unreadCountButton.title = "\(unreadCount)"
                        self.unreadCountButton.isHidden = false
                    } else {
                        self.unreadCountButton.title = ""
                        self.unreadCountButton.isHidden = true
                    }
                }
            }
        }
    }

    var feed: FeedProtocol? {
        didSet {
            if let feed = self.feed {
                self.nameLabel.stringValue = feed.title ?? ""
                if let faviconLink = feed.faviconLink, let url = URL(string: faviconLink) {
                    self.faviconImage.kf.setImage(with: url, placeholder: NSImage(named: "All Articles"))
                } else {
                    self.faviconImage.image = NSImage(named: "All Articles")
                }
                let unreadCount = feed.unreadCount
                if unreadCount > 0 {
                    self.unreadCountButton.title = "\(unreadCount)"
                    self.unreadCountButton.isHidden = false
                } else {
                    self.unreadCountButton.title = ""
                    self.unreadCountButton.isHidden = true
                }
            }
        }
    }
    
}

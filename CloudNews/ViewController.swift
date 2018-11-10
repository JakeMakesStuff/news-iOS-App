//
//  ViewController.swift
//  CloudNews
//
//  Created by Peter Hedlund on 10/20/18.
//  Copyright © 2018 Peter Hedlund. All rights reserved.
//

import Cocoa
import WebKit

class ViewController: NSViewController {

    @IBOutlet var splitView: NSSplitView!
    @IBOutlet var leftTopView: NSView!
    @IBOutlet var centerTopView: NSView!
    @IBOutlet var rightTopView: NSView!
    
    @IBOutlet var feedOutlineView: NSOutlineView!
    @IBOutlet var itemsTableView: NSTableView!
    @IBOutlet var webView: WKWebView!
    
    var toplevelArray = [Any]()
    var itemsArray = [ItemProtocol]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.splitView.setHoldingPriority(NSLayoutConstraint.Priority(rawValue: 249), forSubviewAt: 2)
        self.leftTopView.wantsLayer = true
        self.centerTopView.wantsLayer = true
        self.rightTopView.wantsLayer = true

        self.toplevelArray.append("All Articles")
        self.toplevelArray.append("Starred Articles")
        if let folders = CDFolder.all() {
            self.toplevelArray.append(contentsOf: folders)
        }
        if let feeds = CDFeed.inFolder(folder: 0) {
            self.toplevelArray.append(contentsOf: feeds)
        }
        self.feedOutlineView.reloadData()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        self.leftTopView.layer?.backgroundColor = NSColor(calibratedRed: 0.886, green: 0.890, blue: 0.894, alpha: 1.00).cgColor
        self.centerTopView.layer?.backgroundColor = NSColor(calibratedRed: 0.965, green: 0.965, blue: 0.965, alpha: 1.00).cgColor
        self.rightTopView.layer?.backgroundColor = NSColor(calibratedRed: 0.965, green: 0.965, blue: 0.965, alpha: 1.00).cgColor
        self.feedOutlineView.backgroundColor = NSColor(calibratedRed: 0.886, green: 0.890, blue: 0.894, alpha: 1.00)
    }
    
    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }

    @IBAction func onRefresh(_ sender: Any) {
        NewsManager.shared.sync()
    }
    
}

extension ViewController: NSOutlineViewDataSource {
    
//    Must implement outlineView:numberOfChildrenOfItem:, outlineView:isItemExpandable:, outlineView:child:ofItem: and outlineView:objectValueForTableColumn:byItem:
    
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let folder = item as? FolderProtocol {
            return CDFeed.inFolder(folder: folder.id)?.count ?? 0
        }
        return self.toplevelArray.count
    }
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let _ = item as? FolderProtocol {
            return true
        }
        return false
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let folder = item as? FolderProtocol {
            if let feedArray = CDFeed.inFolder(folder: folder.id) {
                return feedArray[index]
            }
        }
        return self.toplevelArray[index]
    }

//    func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
//        <#code#>
//    }
}

extension ViewController: NSOutlineViewDelegate {
    
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        var view: NSTableCellView?
        if let special = item as? String {
            view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "FeedCell"), owner: self) as? NSTableCellView
            if let textField = view?.textField {
                textField.stringValue = special
                textField.sizeToFit()
            }
            if let imageView = view?.imageView {
                let image = NSImage(named: special)
                imageView.image = image
            }
        } else if let folder = item as? FolderProtocol {
            view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "FolderCell"), owner: self) as? NSTableCellView
            if let textField = view?.textField {
                textField.stringValue = folder.name ?? ""
                textField.sizeToFit()
            }
            if let imageView = view?.imageView {
                let image = NSImage(named: "folder")
                imageView.image = image
            }
        } else if let feed = item as? FeedProtocol {
            view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "FeedCell"), owner: self) as? NSTableCellView
            
            if let textField = view?.textField {
                textField.stringValue = feed.title ?? ""
                textField.sizeToFit()
            }
            if let imageView = view?.imageView, let faviconLink = feed.faviconLink, let url = URL(string: faviconLink) {
                let image = NSImage(byReferencing: url)
                imageView.image = image
            }

        }
        //More code here
        return view
    }
    
    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let outlineView = notification.object as? NSOutlineView else {
            return
        }

        self.itemsArray.removeAll()
        let selectedIndex = outlineView.selectedRow
        
        if selectedIndex == 0 {
            print("All articles selected")
            if let items = CDItem.all() {
                self.itemsArray.append(contentsOf: items)
            }
        } else if selectedIndex == 1 {
            print("Starred articles selected")
            if let items = CDItem.starredItems() {
                self.itemsArray.append(contentsOf: items)
            }
        } else if let folder = outlineView.item(atRow: selectedIndex) as? FolderProtocol {
            print("Folder: \(folder.name ?? "") selected")
        } else if let feed = outlineView.item(atRow: selectedIndex) as? FeedProtocol {
            print("Feed: \(feed.title ?? "") selected")
            if let items = CDItem.items(feed: feed.id) {
                self.itemsArray.append(contentsOf: items)
            }
        }
        self.itemsTableView.reloadData()
    }

}

extension ViewController: NSTableViewDataSource {
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return self.itemsArray.count
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        if self.itemsArray.count > 0 {
            return self.itemsArray[row]
        }
        return nil
    }
}


extension ViewController: NSTableViewDelegate {
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        
//        var image: NSImage?
        var text: String = ""
        var cellIdentifier: String = ""
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .long
        
        let item = self.itemsArray[row]
        
        if tableColumn == tableView.tableColumns[0] {
//            image = item.icon
            text = item.title ?? "No Title"
            cellIdentifier = "ItemCell"
        }
        
        if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: cellIdentifier), owner: nil) as? NSTableCellView {
            cell.textField?.stringValue = text
//            cell.imageView?.image = image ?? nil
            return cell
        }
        return nil
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView else {
            return
        }
        
        let selectedIndex = tableView.selectedRow
        let item = self.itemsArray[selectedIndex]

        if let itemUrl = item.url {
        let url = URL(string: itemUrl)

            if let url = url {
                self.webView.load(URLRequest(url: url))
            }
        }
    }

}

extension ViewController: NSWindowDelegate {
    
    
    
}

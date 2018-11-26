//
//  ArticleHelper.swift
//  CloudNews
//
//  Created by Peter Hedlund on 11/25/18.
//  Copyright © 2018 Peter Hedlund. All rights reserved.
//

import Cocoa

class ArticleHelper {
    
    static var template: String? {
        if let source = Bundle.main.url(forResource: "rss", withExtension: "html") {
            return try? String(contentsOf: source, encoding: .utf8)
        }
        return nil
    }
    
    static func writeAndLoadHtml(html: String, item: ItemProtocol, feedTitle: String? = nil) -> URL? {
//        guard let item = self.item else {
//            return
//        }
//        let summary = SummaryHelper.replaceYTIframe(html)
        var result: URL? = nil
        let summary = html
        if var htmlTemplate = ArticleHelper.template {
            var dateText = "";
            let dateNumber = TimeInterval(item.pubDate)
            let date = Date(timeIntervalSince1970: dateNumber)
            let dateFormat = DateFormatter()
            dateFormat.dateStyle = .medium;
            dateFormat.timeStyle = .short;
            dateText += dateFormat.string(from: date)
            
//            htmlTemplate = htmlTemplate.replacingOccurrences(of: "$ArticleStyle$", with: self.updateCss())
            
            if let feedTitle = feedTitle {
                htmlTemplate = htmlTemplate.replacingOccurrences(of: "$FeedTitle$", with: feedTitle)
            }
            htmlTemplate = htmlTemplate.replacingOccurrences(of: "$ArticleDate$", with: dateText)
            
            if let title = item.title {
                htmlTemplate = htmlTemplate.replacingOccurrences(of: "$ArticleTitle$", with: title)
            }
            if let url = item.url {
                htmlTemplate = htmlTemplate.replacingOccurrences(of: "$ArticleLink$", with: url)
            }
            var author = ""
            if let itemAuthor = item.author, itemAuthor.count > 0 {
                author = "By \(itemAuthor)"
            }
            
            htmlTemplate = htmlTemplate.replacingOccurrences(of: "$ArticleAuthor$", with: author)
            htmlTemplate = htmlTemplate.replacingOccurrences(of: "$ArticleSummary$", with: summary ?? html)
            
            do {
                let containerURL = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                var saveUrl = containerURL.appendingPathComponent("summary")
                saveUrl = saveUrl.appendingPathExtension("html")
                try htmlTemplate.write(to: saveUrl, atomically: true, encoding: .utf8)
//                self.webView?.loadFileURL(saveUrl, allowingReadAccessTo: containerURL)
                result = saveUrl
            } catch {
                //
            }
        }
        return result
    }
/*
    static func updateCss() -> String {
        let fontSize = UserDefaults.standard.integer(forKey: "FontSize")
        
        let screenSize = UIScreen.main.nativeBounds.size
        let margin = UserDefaults.standard.integer(forKey: "MarginPortrait")
        let currentWidth = Int((screenSize.width / UIScreen.main.scale) * CGFloat((Double(margin) / 100.0)))
        
        let marginLandscape = UserDefaults.standard.integer(forKey: "MarginLandscape")
        let currentWidthLandscape = (screenSize.height / UIScreen.main.scale) * CGFloat((Double(marginLandscape) / 100.0))
        
        let lineHeight = UserDefaults.standard.double(forKey: "LineHeight")
        
        return ":root {" +
            "--bg-color: \(PHThemeManager.shared()?.backgroundHex ?? "#FFFFFF");" +
            "--text-color: \(PHThemeManager.shared()?.textHex ?? "#000000");" +
            "--font-size: \(fontSize)px;" +
            "--body-width-portrait: \(currentWidth)px;" +
            "--body-width-landscape: \(currentWidthLandscape)px;" +
            "--line-height: \(lineHeight)em;" +
            "--link-color: \(PHThemeManager.shared()?.linkHex ?? "#1F31B9");" +
            "--footer-link: \(PHThemeManager.shared()?.footerLinkHex ?? "#1F31B9");" +
        "}"
    }
   */
    static func fileUrlInDocumentsDirectory(_ fileName: String, fileExtension: String) -> URL
    {
        do {
            var containerURL = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            containerURL = containerURL.appendingPathComponent(fileName)
            containerURL = containerURL.appendingPathExtension(fileExtension)
            return containerURL
        } catch {
            return URL.init(string: "")!
        }
    }

    

}

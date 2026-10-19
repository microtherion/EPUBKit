//
//  EPUBNavTableOfContentsParser.swift
//  EPUBKit
//
//  Created by Matthias Neeracher on 19/10/2026.
//  Copyright © 2026 Witek Bobrowski. All rights reserved.
//

import Foundation
import AEXML

/// Protocol defining the interface for parsing EPUB table of contents elements from nav files.
///
/// The table of contents parser is responsible for extracting hierarchical navigation
/// information from the NAV toc in the absence of a NCX (Navigation Control file for XML applications) document.
protocol EPUBNavTableOfContentsParser {
    /// Parses an Nav XML element into an EPUBTableOfContents object.
    ///
    /// - Parameter xmlElement: The root XML element of the NCX document.
    /// - Returns: An `EPUBTableOfContents` object containing the parsed navigation hierarchy.
    func parse(_ xmlElement: AEXMLElement) -> EPUBTableOfContents
}

/// Concrete implementation of `EPUBTableOfContentsParser` that parses navigation files.
///
/// This parser extracts hierarchical navigation information from an EPUB 3 style navigation element.
///
/// Expected  XML structure:
/// ```xml
/// <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="en" xml:lang="en">
/// <head>
///  <title>ePub NAV</title>
///  <meta charset="utf-8"/>
///  <link href="../Styles/sgc-nav.css" rel="stylesheet" type="text/css"/>
/// </head>
/// <body epub:type="frontmatter">
///  <nav epub:type="toc" id="toc" role="doc-toc">
///    <h1>Table of Contents</h1>
///    <ol>
///      <li>
///        <a href="Section0001.xhtml">1 The world is everything that is the case.</a>
///      <ol>
///      <li>
///        <a href="Section0001.xhtml#sigil_toc_id_1">1.1 The world is the totality of facts, not of things.</a>
///        <ol>
///          <li>
///            <a href="Section0001.xhtml#sigil_toc_id_2">1.11 The world is determined by the facts, and by these being all the facts.</a>
///          </li>
///          <li>
///            <a href="Section0001.xhtml#sigil_toc_id_3">1.12 For the totality of facts determines both what is the case, and also all that is not the case.</a>
///          </li>
///       </ol>
///       </li>
///       <li>
///         <a href="Section0001.xhtml#sigil_toc_id_5">1.2 The world divides into facts.</a>
///       </li>
///     </ol>
///     </li>
///     <li>
///       <a href="Section0001.xhtml#sigil_toc_id_7">2 What is the case, the fact, is the existence of atomic facts.</a>
///     <ol>
///       <li>
///         <a href="Section0001.xhtml#sigil_toc_id_8">2.01 An atomic fact is a combination of objects (entities, things).</a>
///       </li>
///     </ol>
///      </li>
///    </ol>
///  </nav>
///<nav epub:type="landmarks" id="landmarks" hidden="">
///   <h2>Landmarks</h2>
///    <ol>
///      <li>
///        <a epub:type="toc" href="#toc">Table of Contents</a>
///      </li>
///    </ol>
///  </nav>
///</body>
///</html>
/// ```
///
/// The NCX specification is part of the DAISY Digital Talking Book standard and provides
/// a structured way to represent navigation hierarchies in digital publications.
class EPUBNavTableOfContentsParserImplementation: EPUBNavTableOfContentsParser {

    /// Parses the Nav document to extract the complete navigation hierarchy.
    ///
    /// The parsing process:
    /// 1. Extracts the document title from the `<docTitle>` element
    /// 2. Looks for the unique identifier in the `<head>` metadata
    /// 3. Recursively parses the `<navMap>` to build the navigation tree
    /// 4. Creates a root `EPUBTableOfContents` object containing all navigation points
    ///
    /// The NCX format allows for deeply nested navigation structures, where each
    /// `<navPoint>` can contain child `<navPoint>` elements to represent sub-sections,
    /// sub-chapters, or other hierarchical content organization.
    ///
    /// - Parameter xmlElement: The root XML element of the NCX document.
    /// - Returns: An `EPUBTableOfContents` object representing the complete navigation hierarchy.
    func parse(_ xmlElement: AEXMLElement) -> EPUBTableOfContents {
        // STEP 1: Create the root table of contents object
        // The NCX docTitle provides the overall publication title for navigation
        // This may differ from the dc:title in metadata if a shorter form is desired
        var tableOfContents = EPUBTableOfContents(
            label: "",
            id: "0", // Root level uses a synthetic ID since NCX root has no id attribute
            item: "", // Reference to the unique identifier for cross-document validation
            subTable: [] // Will be populated recursively with the navigation hierarchy
        )
        
        // STEP 2: Recursively parse the navigation map to build the complete hierarchy
        // The navMap contains the root-level navPoints, each of which may contain
        // nested navPoints creating a tree structure for complex documents
        if let navToc = xmlElement["body"].firstDescendant(where: { $0.name == "nav" && $0.attributes["epub:type"] == "toc"}) {
            tableOfContents.subTable = evaluateChildren(from: navToc)
        }

        return tableOfContents
    }

}

extension EPUBNavTableOfContentsParserImplementation {

    /// Recursively evaluates navigation points to build the hierarchical table of contents.
    ///
    /// This method processes `<li>` elements within the navigation document, extracting:
    /// - Content sources (file paths or URLs to the actual content)
    /// - Unique identifiers for each navigation point
    /// - Nested navigation points for sub-sections
    ///
    /// The recursive nature allows for unlimited nesting depth, supporting complex
    /// document structures with multiple levels of organization (parts, chapters,
    /// sections, subsections, etc.).
    ///
    /// - Parameter xmlElement: The XML element containing navPoint children (navMap or navPoint).
    /// - Returns: An array of `EPUBTableOfContents` objects representing the navigation hierarchy.
    private func evaluateChildren(from xmlElement: AEXMLElement) -> [EPUBTableOfContents] {
        // STEP 1: Get all navPoint elements from the current level
        // Return empty array if no navPoints exist (base case for recursion)
        guard let points = xmlElement["ol"]["li"].all else { return [] }
        
        // STEP 2: Process each navPoint to create table of contents entries
        // This mapping operation transforms XML navPoint elements into our domain model
        let subs: [EPUBTableOfContents] = points.map { point in
            EPUBTableOfContents(
                // Extract the display label from navLabel/text
                // This is the text that will be shown in the table of contents UI
                // Fallback to empty string for malformed NCX files
                label: point["a"].value ?? point["span"].value ?? "",

                // Synthesize ID, since nav files don't have that
                id: UUID().uuidString,

                // Extract the content source from the content element
                // This href points to the actual XHTML content file, potentially with a fragment identifier
                // Not all TOC entries must be linked, so this can be empty
                item: point["a"].attributes["href"] ?? "",

                // RECURSIVE STEP: Process any nested navPoints
                // This is the core of the recursive algorithm - each navPoint can contain
                // child navPoints, creating unlimited nesting depth for complex documents
                // The recursion naturally handles the tree traversal and construction
                subTable: evaluateChildren(from: point)
            )
        }
        
        return subs
    }

}

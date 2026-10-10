import SCCore
import SwiftUI

extension DesktopView {
    /// Every menu with its items. Items that can't exist on a Mac are listed dimmed, with
    /// help text saying why.
    var menus: [(String, [MenuEntry])] {
        let hasScreen = model.screen != nil, hasTrue = model.trueColor != nil, hasMono = model.mono != nil
        let waiting = !model.queue.isEmpty
        func absent(_ title: String, _ help: String) -> MenuEntry { MenuEntry(title, help, enabled: false) }
        return [
            ("\u{F8FF}", [
                MenuEntry("About GS Remap...", "Shows the program's name and credits.") { model.overlay = .about },
                MenuEntry("Help!", "Opens the help window, with a page for each menu.") {
                    model.helpTopic = 0
                    model.overlay = .help
                },
                MenuEntry("Menu item help", "Pick this, then pick any menu item, dimmed ones included, to read what it does.") {
                    model.pickingHelp = true
                },
                .divider,
                MenuEntry("Preferences...", "Chooses the font used for the whole desktop.") { model.overlay = .preferences },
            ]),
            ("File", [
                MenuEntry("Load & convert...", "Loads a picture in the format selected in the Load formats window. Pick several files to work through them one at a time.") { model.load() },
                MenuEntry("Re-convert last file", "Loads the most recent file again.", enabled: model.canReload) { model.reload() },
                MenuEntry("Load next", "Loads the next file left over from a multiple-file Load.", enabled: waiting) { model.loadNext() },
                MenuEntry("Cancel remaining files", "Forgets the files left over from a multiple-file Load.", enabled: waiting) { model.queue = [] },
                .divider,
                MenuEntry("Save conversion...", "Saves the screen image in the format selected in the Save formats window.", enabled: hasScreen) { model.save() },
                MenuEntry("Exchange load/save paths", "Swaps the folders the Load and Save panels start in, for checking a file you just saved.") { model.exchangePaths() },
                .divider,
                MenuEntry("Print (normal)...", "Prints the screen image as large as fits the page.", enabled: hasScreen) { model.printNormal() },
                MenuEntry("Print (enhanced)...", "Prints with a size you choose, optional centering and a one-line caption. Uses the true color image when there is one.",
                          enabled: hasScreen || hasTrue) { model.overlay = .printOptions },
                MenuEntry("Print alignment page...", "Prints a page with a mark in each corner of the printable area.") { Printing.run(.alignment) },
                .divider,
                MenuEntry("Examine file...", "Shows any file as hexadecimal and text, or as a chart of how often each byte value occurs.") { model.examine() },
                .divider,
                MenuEntry("Quit", "Leaves the program. Unsaved conversions are lost without warning.") { NSApp.terminate(nil) },
            ]),
            ("Edit", [
                absent("Undo", "On the IIgs the Edit menu served desk accessories only. There is no undo."),
                .divider,
                MenuEntry("Copy", "Puts the picture shown in the Image window on the clipboard.", enabled: model.hasImage) { model.copyImage() },
                MenuEntry("Paste", "Loads the picture on the clipboard as a true color image.") { model.paste() },
                absent("Clear", "On the IIgs the Edit menu served desk accessories only."),
                .divider,
                MenuEntry("Close", "Discards every image in memory.", enabled: model.hasImage) { model.closeImage() },
            ]),
            ("Screen", [
                MenuEntry("Screen image info...", "Size, graphic mode and color count of the screen image.", enabled: hasScreen) { model.screenInfo() },
                MenuEntry("Convert to true color...", "Makes a true color image from the screen image, ready for filters or another Remap.", enabled: hasScreen) { model.convertToTrueColor() },
                MenuEntry("Convert to monochrome...", "Makes a black & white, one bit per pixel image from the screen image.", enabled: hasScreen) { model.overlay = .toMono(true) },
                .divider,
                MenuEntry("View full screen", "Shows the screen image by itself. Click to return.", enabled: hasScreen) { model.overlay = .fullScreen },
                MenuEntry("View half size", "Shows the screen image at half size, so large pictures fit. Click to return.", enabled: hasScreen) { model.overlay = .viewer(0) },
                MenuEntry("View X4 magnified", "Shows the screen image four times larger. Move the mouse to look around; click to return.", enabled: hasScreen) { model.overlay = .viewer(1) },
                absent("View interlaced on VOC", "Needs the Apple Video Overlay Card, which a Mac doesn't have."),
                .divider,
                MenuEntry("Store palette", "Remembers this picture's palette for the Stored palette choice in Remap.", enabled: hasScreen) { model.storePalette() },
                MenuEntry("Use as desktop background", "Puts the screen image behind the windows in place of the light blue desktop.", enabled: hasScreen) { model.useAsDesktop() },
                absent("Oscilloscope Art", "Drew the picture on an oscilloscope wired to the IIgs video jack."),
            ]),
            ("True color", [
                MenuEntry("True color image info...", "Size and color count of the true color image.", enabled: hasTrue) { model.trueColorInfo() },
                MenuEntry("Convert to screen (Remap)...", "Turns the true color image into a screen image with the mode, palette and dithering you choose.",
                          enabled: hasScreen || hasTrue) { model.beginRemap() },
                MenuEntry("Convert to monochrome...", "Makes a black & white, one bit per pixel image from the true color image.", enabled: hasTrue) { model.overlay = .toMono(false) },
                MenuEntry("View approximation", "Shows the true color image by itself. Click to return.", enabled: hasTrue) { model.overlay = .viewer(2) },
                .divider,
                MenuEntry("Mirror image", "Swaps left and right.", enabled: hasTrue) { model.transform(1) },
                MenuEntry("Flip image", "Swaps top and bottom.", enabled: hasTrue) { model.transform(2) },
                MenuEntry("Rotate image", "Turns the image a quarter turn.", enabled: hasTrue) { model.transform(5) },
                .divider,
                MenuEntry("Histogram equalization", "Spreads brightness levels evenly. Helps dark or washed-out pictures.", enabled: hasTrue) {
                    model.filter("Equalizing image") { Filters.equalize($0) }
                },
                MenuEntry("Median filter", "Replaces each pixel by the middle value of its neighbours. Removes specks.", enabled: hasTrue) {
                    model.filter("Performing median filter") { Filters.median($0) }
                },
                MenuEntry("Sigma filter", "Averages each pixel with its neighbours.", enabled: hasTrue) {
                    model.filter("Performing sigma filter") { Filters.sigma($0) }
                },
                MenuEntry("Emboss image", "Gives a raised, 3-D look.", enabled: hasTrue) {
                    model.filter("Embossing image") { Filters.emboss($0) }
                },
                MenuEntry("Blur image...", "Softens the picture. Asks for a factor from 0 to 99.", enabled: hasTrue) { model.overlay = .factor(0) },
                MenuEntry("Sharpen image...", "Makes edges crisper. Asks for a factor from 0 to 99.", enabled: hasTrue) { model.overlay = .factor(1) },
                MenuEntry("Solarize image", "Inverts the bright half of the tones.", enabled: hasTrue) {
                    model.filter("Solarizing image") { Filters.solarize($0) }
                },
                MenuEntry("Find edges...", "Keeps outlines and turns the rest black. Asks for a factor from 0 to 99.", enabled: hasTrue) { model.overlay = .factor(2) },
                MenuEntry("Increase contrast", "Makes lights lighter and darks darker.", enabled: hasTrue) {
                    model.filter("Increasing contrast") { Filters.contrast($0, increase: true) }
                },
                MenuEntry("Decrease contrast", "Pulls lights and darks toward the middle.", enabled: hasTrue) {
                    model.filter("Decreasing contrast") { Filters.contrast($0, increase: false) }
                },
            ]),
            ("Monochrome", [
                MenuEntry("Monochrome image info...", "Counts the white pixels in the monochrome image.", enabled: hasMono) { model.monoInfo() },
                MenuEntry("Convert to screen...", "Makes a screen image from the monochrome image.", enabled: hasMono) { model.overlay = .fromMono(true) },
                MenuEntry("Convert to true color...", "Makes a true color image from the monochrome image.", enabled: hasMono) { model.overlay = .fromMono(false) },
                MenuEntry("Negative image", "Exchanges black and white.", enabled: hasMono) { model.negateMono() },
            ]),
            ("Windows", [
                MenuEntry("Normal positions", "The three windows stay in their normal places; this brings Load formats to the front.") { model.activeWindow = 0 },
                MenuEntry("Load formats", "Brings the Load formats window to the front.") { model.activeWindow = 0 },
                MenuEntry("Save formats", "Brings the Save formats window to the front.") { model.activeWindow = 1 },
                MenuEntry("Current image", "Brings the Image window to the front.") { model.activeWindow = 2 },
            ]),
            ("Extras", [
                MenuEntry("Available font list", "Makes a picture listing the fonts on this Mac, each name drawn in its own font.") { model.fontList(continuing: false) },
                MenuEntry("More available fonts", "Makes the next page of the font list.", enabled: model.moreFonts) { model.fontList(continuing: true) },
                absent("Font key chart...", "Charted every character of a IIgs font with its key. Not available."),
                absent("Print banner...", "Printed banners across several pages of fan-fold paper. Not available."),
                .divider,
                MenuEntry("Revert to normal desktop", "Removes a picture placed with Use as desktop background.", enabled: model.desktopImage != nil) { model.desktopImage = nil },
                MenuEntry("System info report...", "Lists the program version, this Mac's system and the images in memory.") { model.systemInfo() },
            ]),
        ]
    }
}

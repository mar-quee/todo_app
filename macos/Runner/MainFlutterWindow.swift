import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    
    // ウィンドウの最小サイズを設定
    self.minSize = NSSize(width: 450, height: 600)
    
    // バックグラウンドカラーを設定
    self.backgroundColor = NSColor.white
    
    // ウィンドウスタイルを設定
    self.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    self.titleVisibility = .visible
    self.titlebarAppearsTransparent = false
    
    // ウィンドウの位置を中央に設定
    self.center()
    
    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}

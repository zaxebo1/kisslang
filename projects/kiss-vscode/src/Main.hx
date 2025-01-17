#if !test
import vscode.*;
import ktxt2.*;
import ktxt2.KTxt2.KTxt2Conversion;
#end
import Sys;
import sys.io.File;
import sys.FileSystem;
import kiss.Prelude;
import haxe.io.Path;
import js.Node;
import js.node.ChildProcess;
import uuid.Uuid;
import re_flex.R;

using StringTools;
using uuid.Uuid;

typedef Command = (?String) -> Void;

typedef KissConfig = {
    registerBuiltins:() -> Void,
    registerCommand:(String, Command) -> Void,
    prepareInterp:() -> Void,
    runCommand:Command,
    runLastCommand:Command,
    runKeyboardShortcut:Command,
    tryLoadConfig:Command,
    extensionPath:String,
    #if !test
    conversions:Array<KTxt2Conversion>,
    #end
    init:() -> Void
};

@:build(kiss.Kiss.build())
class Main {
    // TODO support EMeta(s:MetadataEntry, e:Expr) via Kiss so this signature can be moved to Main.kiss
    #if !test
    @:expose("activate")
    static function activate(context:ExtensionContext) {
        _activate(context);
    }
    #end
}

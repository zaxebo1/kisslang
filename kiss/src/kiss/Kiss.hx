package kiss;

#if macro
import haxe.Exception;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.ExprTools;
import haxe.macro.PositionTools;
import haxe.io.Path;
import sys.io.File;
import kiss.Stream;
import kiss.Reader;
import kiss.ReaderExp;
import kiss.FieldForms;
import kiss.SpecialForms;
import kiss.Macros;
import kiss.KissError;
import kiss.cloner.Cloner;
import tink.syntaxhub.*;

using kiss.Kiss;
using kiss.Helpers;
using kiss.Reader;
using tink.MacroApi;
using haxe.io.Path;

typedef ExprConversion = (ReaderExp) -> Expr;

typedef FormDoc = {
    minArgs:Null<Int>,
    maxArgs:Null<Int>,
    ?expectedForm:String,
    ?doc:String
};

typedef KissState = {
    className:String,
    file:String,
    readTable:ReadTable,
    startOfLineReadTable:ReadTable,
    startOfFileReadTable:ReadTable,
    endOfFileReadTable:ReadTable,
    fieldForms:Map<String, FieldFormFunction>,
    specialForms:Map<String, SpecialFormFunction>,
    macros:Map<String, MacroFunction>,
    formDocs:Map<String, FormDoc>,
    doc:(String, Null<Int>, Null<Int>, ?String, ?String)->Void,
    wrapListExps:Bool,
    loadedFiles:Map<String, Null<ReaderExp>>,
    callAliases:Map<String, ReaderExpDef>,
    identAliases:Map<String, ReaderExpDef>,
    fieldList:Array<Field>,
    // TODO This map was originally created to track whether the programmer wrote their own main function, but could also
    // be used to allow macros to edit fields that were already defined (for instance, to decorate a function or add something
    // to the constructor body)
    fieldDict:Map<String, Field>,
    loadingDirectory:String,
    hscript:Bool,
    macroVars:Map<String, Dynamic>,
    collectedBlocks:Map<String, Array<ReaderExp>>,
    inStaticFunction:Bool,
    typeHints:Array<Var>,
    varsInScope:Array<Var>,
    localVarsInScope:Array<Var>,
    conversionStack:Array<ReaderExp>,
    stateChanged:Bool
};
#end

class Kiss {
    #if macro
    public static function defaultKissState(?context:FrontendContext):KissState {
        var className = if (context == null) {
            Context.getLocalClass().get().name;
        } else {
            context.name;
        }
        var k = {
            className: className,
            file: "",
            readTable: Reader.builtins(),
            startOfLineReadTable: new ReadTable(),
            startOfFileReadTable: new ReadTable(),
            endOfFileReadTable: new ReadTable(),
            fieldForms: new Map(),
            specialForms: null,
            macros: null,
            formDocs: new Map(),
            doc: null,
            wrapListExps: true,
            loadedFiles: new Map<String, ReaderExp>(),
            // Helpful built-in aliases
            // These ones might conflict with a programmer's variable names, so they only apply in call expressions:
            callAliases: [
                // TODO some of these probably won't conflict, and could be passed as functions for a number of reasons
                "print" => Symbol("Prelude.print"),
                "sort" => Symbol("Prelude.sort"),
                "sortBy" => Symbol("Prelude.sortBy"),
                "groups" => Symbol("Prelude.groups"),
                "pairs" => Symbol("Prelude.pairs"),
                "reverse" => Symbol("Prelude.reverse"),
                "memoize" => Symbol("Prelude.memoize"),
                "fsMemoize" => Symbol("Prelude.fsMemoize"),
                "symbolName" => Symbol("Prelude.symbolName"),
                "symbolNameValue" => Symbol("Prelude.symbolNameValue"),
                "symbol" => Symbol("Prelude.symbol"),
                "expList" => Symbol("Prelude.expList"),
                "map" => Symbol("Lambda.map"),
                "filter" => Symbol("Prelude.filter"),
                "flatten" => Symbol("Lambda.flatten"),
                "has" => Symbol("Lambda.has"),
                "count" => Symbol("Lambda.count"),
                "enumerate" => Symbol("Prelude.enumerate"),
                "assertProcess" => Symbol("Prelude.assertProcess"),
                "tryProcess" => Symbol("Prelude.tryProcess"),
                "libPath" => Symbol("Prelude.libPath"),
                "random" => Symbol("Std.random"),
                "walkDirectory" => Symbol("Prelude.walkDirectory"),
                "purgeDirectory" => Symbol("Prelude.purgeDirectory"),
                "getTarget" => Symbol("Prelude.getTarget"),
                // These work with (apply) because they are added as "opAliases" in Macros.kiss:
                "min" => Symbol("Prelude.min"),
                "max" => Symbol("Prelude.max"),
                "iHalf" => Symbol("Prelude.iHalf"),
                "iThird" => Symbol("Prelude.iThird"),
                "iFourth" => Symbol("Prelude.iFourth"),
                "iFifth" => Symbol("Prelude.iFifth"),
                "iSixth" => Symbol("Prelude.iSixth"),
                "iSeventh" => Symbol("Prelude.iSeventh"),
                "iEighth" => Symbol("Prelude.iEighth"),
                "iNinth" => Symbol("Prelude.iNinth"),
                "iTenth" => Symbol("Prelude.iTenth"),
                "fHalf" => Symbol("Prelude.fHalf"),
                "fThird" => Symbol("Prelude.fThird"),
                "fFourth" => Symbol("Prelude.fFourth"),
                "fFifth" => Symbol("Prelude.fFifth"),
                "fSixth" => Symbol("Prelude.fSixth"),
                "fSeventh" => Symbol("Prelude.fSeventh"),
                "fEighth" => Symbol("Prelude.fEighth"),
                "fNinth" => Symbol("Prelude.fNinth"),
                "fTenth" => Symbol("Prelude.fTenth"),
                "uuid" => Symbol("Prelude.uuid"),
            ],
            identAliases: [
                // These ones won't conflict with variables and might commonly be used with (apply)
                "+" => Symbol("Prelude.add"),
                "-" => Symbol("Prelude.subtract"),
                "*" => Symbol("Prelude.multiply"),
                "/" => Symbol("Prelude.divide"),
                "%" => Symbol("Prelude.mod"),
                "^" => Symbol("Prelude.pow"),
                ">" => Symbol("Prelude.greaterThan"),
                ">=" => Symbol("Prelude.greaterEqual"),
                "<" => Symbol("Prelude.lessThan"),
                "<=" => Symbol("Prelude.lesserEqual"),
                "=" => Symbol("Prelude.areEqual"),
                // These ones *probably* won't conflict with variables and might be passed as functions
                "chooseRandom" => Symbol("Prelude.chooseRandom"),
                // These ones *probably* won't conflict with variables and might commonly be used with (apply) because they are variadic
                "joinPath" => Symbol("Prelude.joinPath"),
                "readDirectory" => Symbol("Prelude.readDirectory"),
                "substr" => Symbol("Prelude.substr"),
                "isListExp" => Symbol("Prelude.isListExp")
                /* zip functions used to live here as aliases but now they are macros that also
                apply (the Array<Array<Dynamic>>) to the result */
                /* intersect used to live here as an alias but now it is in a macro that also
                applies (the Array<Array<Dynamic>>) to the result */
                /* concat used to live here as an alias but now it is in a macro that also
                applies (the Array<Dynamic>) to the result */
            ],
            fieldList: [],
            fieldDict: new Map(),
            loadingDirectory: "",
            hscript: false,
            macroVars: new Map(),
            collectedBlocks: new Map(),
            inStaticFunction: false,
            typeHints: [],
            varsInScope: [],
            localVarsInScope: [],
            conversionStack: [],
            stateChanged: false
        };

        k.doc = (form:String, minArgs:Null<Int>, maxArgs:Null<Int>, expectedForm = "", doc = "") -> {
            k.formDocs[form] = {
                minArgs: minArgs,
                maxArgs: maxArgs,
                expectedForm: expectedForm,
                doc: doc
            };
            return;
        };

        FieldForms.addBuiltins(k);
        k.specialForms = SpecialForms.builtins(k, context);
        k.macros = Macros.builtins(k);

        return k;
    }

    public static function _try<T>(operation:() -> T):Null<T> {
        #if !macrotest
        try {
        #end
            return operation();
        #if !macrotest
        } catch (err:StreamError) {
            Sys.stderr().writeString(err + "\n");
            Sys.exit(1);
            return null;
        } catch (err:KissError) {
            Sys.stderr().writeString(err + "\n");
            Sys.exit(1);
            return null;
        } catch (err:UnmatchedBracketSignal) {
            Sys.stderr().writeString(Stream.toPrint(err.position) + ': Unmatched ${err.type}\n');
            Sys.exit(1);
            return null;
        } catch (err:Exception) {
            Sys.stderr().writeString("Error: " + err.message + "\n");
            Sys.stderr().writeString(err.stack.toString() + "\n");
            Sys.exit(1);
            return null;
        }
        #end
    }

    /**
     * Initializer macro: suppress some compiler warnings that Kiss code commonly generates
     * Source: https://try.haxe.org/#10F18962 by @kLabz
     */
    public static macro function setup() {
        haxe.macro.Context.onAfterTyping(function(_) {
            haxe.macro.Context.filterMessages(function(msg) {
                return switch (msg) {
                    case Warning("This case is unused", _): false;
                    case _: true;
                };
            });
        });
      
        return macro {};
    }
    #end
    public static macro function exp(kissCode:ExprOf<String>) {
        var pos = kissCode.pos;
        var pos = PositionTools.getInfos(pos);
        var kissCode = ExprTools.getValue(kissCode);

        var content = File.getContent(pos.file).substr(0, pos.min);
        var lines:kiss.List<String> = content.split('\n');
        var lineNumber = lines.length;
        var column = lines[-1].length + 1;
        var pos = {
            file: pos.file,
            absoluteChar: pos.min,
            line: lineNumber,
            column: column
        };
        
        return _try(() -> {
            var exp = null;
            var stream = Stream.fromString(kissCode, pos);
            var k = defaultKissState();
            Reader.readAndProcess(stream, k, (nextExp) -> {
                if (exp == null) {
                    exp = readerExpToHaxeExpr(nextExp, k);
                } else {
                    throw KissError.fromExp(nextExp, "can't have multiple top-level expressions in Kiss.exp() input");
                }
            });
            return exp;
        });
    }
    #if macro
    /**
        Build macro: add fields to a class from a corresponding .kiss file
    **/
    public static function build(?kissFile:String, ?k:KissState, useClassFields = true, ?context:FrontendContext):Array<Field> {

        var classPath = Context.getPosInfos(Context.currentPos()).file;
        // (load... ) relative to the original file
        var loadingDirectory = Path.directory(classPath);
        if (kissFile == null) {
            kissFile = classPath.withoutDirectory().withoutExtension().withExtension("kiss");
        }
        //trace('kiss build $kissFile');

        return _try(() -> {
            #if profileKiss
            haxe.Timer.measure(() -> {
                trace(kissFile);
            #end
                if (k == null)
                    k = defaultKissState(context);

                if (useClassFields) {
                    k.fieldList = Context.getBuildFields();
                    for (field in k.fieldList) {
                        k.fieldDict[field.name] = field;
                    }
                }
                k.loadingDirectory = loadingDirectory;

                var topLevelBegin = load(kissFile, k);

                if (topLevelBegin != null) {
                    // If no main function is defined manually, Kiss expressions at the top of a file will be put in a main function.
                    // If a main function IS defined, this will result in an error
                    if (k.fieldDict.exists("main")) {
                        throw KissError.fromExp(topLevelBegin, '$kissFile has expressions outside of field definitions, but already defines its own main function.');
                    }
                    var b = topLevelBegin.expBuilder();
                    // This doesn't need to be added to the fieldDict because all code generation is done
                    k.fieldList.push({
                        name: "main",
                        access: [AStatic,APublic],
                        kind: FFun(Helpers.makeFunction(
                            b.symbol("main"),
                            false,
                            b.list([]),
                            [topLevelBegin],
                            k,
                            "function",
                            [])),
                        pos: topLevelBegin.macroPos()
                    });
                }

                k.fieldList;
            #if profileKiss
            });
            #end
        });
    }

    public static function load(kissFile:String, k:KissState, ?loadingDirectory:String, loadAllExps = false):Null<ReaderExp> {
        if (loadingDirectory == null)
            loadingDirectory = k.loadingDirectory;

        var fullPath = if (Path.isAbsolute(kissFile)) {
            kissFile;
        } else {
            Path.join([loadingDirectory, kissFile]);
        };
        var previousFile = k.file;
        k.file = fullPath;

        if (k.loadedFiles.exists(fullPath)) {
            return k.loadedFiles[fullPath];
        }
        var stream = Stream.fromFile(fullPath);
        var startPosition = stream.position();
        var loadedExps = [];
        Reader.readAndProcess(stream, k, (nextExp) -> {
            #if test
            Sys.println(nextExp.def.toString());
            #end

            // readerExpToHaxeExpr must be called to process readermacro, alias, and macro definitions
            macroUsed = false;
            var expr = readerExpToHaxeExpr(nextExp, k);

            // exps in the loaded file that actually become haxe expressions can be inserted into the
            // file that loaded them at the position (load) was called.
            // conditional compiler macros like (#when) tend to return empty blocks, or blocks containing empty blocks
            // when they contain field forms, so this should also be ignored
            function isEmpty(expr) {
                switch (expr.expr) {
                    case EBlock([]):
                    case EBlock(blockExps):
                        for (exp in blockExps) {
                            if (!isEmpty(exp))
                                return false;
                        }
                    default:
                        return false;
                }
                return true;
            }
            // When calling from build(), we can't add all expressions to the (begin) returned by (load), because that will
            // cause double-evaluation of field forms
            if (loadAllExps) {
                loadedExps.push(nextExp);
            } else if (!isEmpty(expr)) {
                // don't double-compile macros:
                if (macroUsed) {
                    loadedExps.push(RawHaxe(expr.toString()).withPosOf(nextExp));
                } else {
                    loadedExps.push(nextExp);
                }
            }
        });

        var exp = if (loadedExps.length > 0) {
            CallExp(Symbol("begin").withPos(startPosition), loadedExps).withPos(startPosition);
        } else {
            null;
        }
        k.loadedFiles[fullPath] = exp;
        k.file = previousFile;
        return exp;
    }

    /**
     * Build macro: add fields to a Haxe class by compiling multiple Kiss files in order with the same KissState
     */
    public static function buildAll(kissFiles:Array<String>, ?k:KissState, useClassFields = true):Array<Field> {
        if (k == null)
            k = defaultKissState();

        if (useClassFields) {
            k.fieldList = Context.getBuildFields();
            for (field in k.fieldList) {
                k.fieldDict[field.name] = field;
            }
        }

        for (file in kissFiles) {
            build(file, k, false);
        }

        return k.fieldList;
    }

    static var macroUsed = false;
    static var expCache:haxe.DynamicAccess<String> = null;
    static var cacheFile = ".kissCache.json";
    static var cacheThreshold = 0.2;
    public static function readerExpToHaxeExpr(exp:ReaderExp, k:KissState):Expr {
        #if kissCache
        if (expCache == null) {
            expCache = if (sys.FileSystem.exists(cacheFile)) {
                haxe.Json.parse(File.getContent(cacheFile));
            } else {
                {};
            }
        }
        var str = Reader.toString(exp.def);
        if (expCache.exists(str)) {
            return Context.parse(expCache[str], Helpers.macroPos(exp));
        }
        #end
        
        if (k.conversionStack.length == 0) k.stateChanged = false;
        k.conversionStack.push(exp);
        
        var macros = k.macros;
        var fieldForms = k.fieldForms;
        var specialForms = k.specialForms;
        var formDocs = k.formDocs;

        // Bind the table arguments of this function for easy recursive calling/passing
        var convert = readerExpToHaxeExpr.bind(_, k);

        function checkNumArgs(form:String) {
            if (formDocs.exists(form)) {
                var docs = formDocs[form];
                // null docs can get passed around by renameAndDeprecate functions. a check here is more DRY
                if (docs != null)
                    exp.checkNumArgs(docs.minArgs, docs.maxArgs, docs.expectedForm);
            }
        }

        if (k.hscript)
            exp = Helpers.removeTypeAnnotations(exp);

        var none = EBlock([]).withMacroPosOf(exp);

        var startTime = haxe.Timer.stamp();
        var expr = switch (exp.def) {
            case None:
                none;
            case Symbol(alias) if (k.identAliases.exists(alias)):
                readerExpToHaxeExpr(k.identAliases[alias].withPosOf(exp), k);
            case Symbol(name):
                try {
                    Context.parse(name, exp.macroPos());
                } catch (err:haxe.Exception) {
                    throw KissError.fromExp(exp, "invalid symbol");
                };
            case StrExp(s):
                EConst(CString(s)).withMacroPosOf(exp);
            case CallExp({pos: _, def: Symbol(ff)}, args) if (fieldForms.exists(ff)):
                checkNumArgs(ff);
                var field = fieldForms[ff](exp, args.copy(), k);
                k.fieldList.push(field);
                k.fieldDict[field.name] = field;
                k.stateChanged = true;
                none; // Field forms are no-ops
            case CallExp({pos: _, def: Symbol(mac)}, args) if (macros.exists(mac)):
                checkNumArgs(mac);    
                macroUsed = true;
                var expanded = macros[mac](exp, args.copy(), k);
                if (expanded != null) {
                    convert(expanded);
                } else {
                    none;
                };
            case CallExp({pos: _, def: Symbol(specialForm)}, args) if (specialForms.exists(specialForm)):
                checkNumArgs(specialForm);    
                specialForms[specialForm](exp, args.copy(), k);
            case CallExp({pos: _, def: Symbol(alias)}, args) if (k.callAliases.exists(alias)):
                convert(CallExp(k.callAliases[alias].withPosOf(exp), args).withPosOf(exp));
            case CallExp(func, args):
                ECall(convert(func), [for (argExp in args) convert(argExp)]).withMacroPosOf(exp);
            case ListExp(elements):
                var isMap = false;
                var arrayDecl = EArrayDecl([
                    for (elementExp in elements) {
                        switch (elementExp.def) {
                            case KeyValueExp(_, _):
                                isMap = true;
                            default:
                        }
                        convert(elementExp);
                    }
                ]).withMacroPosOf(exp);
                if (!isMap && k.wrapListExps && !k.hscript) {
                    ENew({
                        pack: ["kiss"],
                        name: "List"
                    }, [arrayDecl]).withMacroPosOf(exp);
                } else {
                    arrayDecl;
                };
            case RawHaxe(code):
                try {
                    Context.parse(code, exp.macroPos());
                } catch (err:Exception) {
                    throw KissError.fromExp(exp, 'Haxe parse error: $err');
                };
            case RawHaxeBlock(code):
                try {
                    Context.parse('{$code}', exp.macroPos());
                } catch (err:Exception) {
                    throw KissError.fromExp(exp, 'Haxe parse error: $err');
                };
            case FieldExp(field, innerExp):
                EField(convert(innerExp), field).withMacroPosOf(exp);
            case KeyValueExp(keyExp, valueExp):
                EBinop(OpArrow, convert(keyExp), convert(valueExp)).withMacroPosOf(exp);
            case Quasiquote(innerExp):
                // This statement actually turns into an HScript expression before running
                macro {
                    Helpers.evalUnquotes($v{innerExp}).def;
                };
            default:
                throw KissError.fromExp(exp, 'conversion not implemented');
        };
        var conversionTime = haxe.Timer.stamp() - startTime;
        k.conversionStack.pop();
        #if kissCache
        if (conversionTime > cacheThreshold && !k.stateChanged) {
            expCache[str] = expr.toString();
            File.saveContent(cacheFile, haxe.Json.stringify(expCache));
        }
        #end

        return expr;
    }
    
    public static function addVarInScope(k: KissState, v:Var, local:Bool) {
        if (v.type != null)
            k.typeHints.push(v);
        k.varsInScope.push(v);
        if (local)
            k.localVarsInScope.push(v);
    }

    public static function removeVarInScope(k: KissState, v:Var, local:Bool) {
        function removeLast(list:Array<Var>, v:Var) {
            var index = list.lastIndexOf(v);
            list.splice(index, 1);
        }
        if (v.type != null)
            removeLast(k.typeHints, v);
        removeLast(k.varsInScope, v);
        if (local)
            removeLast(k.localVarsInScope, v);
    }

    static function disableMacro(copy:KissState, m:String, reason:String) {
        copy.macros[m] = (wholeExp:ReaderExp, exps, k) -> {
            var b = wholeExp.expBuilder();
            // have this throw during macroEXPANSION, not before (so assertThrows will catch it)
            b.throwKissError('$m is unavailable in macros because $reason');
        };
    }

    // This doesn't clone k because k might be modified in important ways :(
    public static function forStaticFunction(k:KissState, inStaticFunction:Bool) {
        k.inStaticFunction = inStaticFunction;
        return k;
    }

    // Return an identical Kiss State, but without type annotations or wrapping list expressions as kiss.List constructor calls.
    public static function forHScript(k:KissState):KissState {
        var copy = new Cloner().clone(k);
        copy.hscript = true;

        // disallow macros that will error when run in hscript:
        disableMacro(copy, "ifLet", "hscript doesn't support pattern-matching");
        disableMacro(copy, "whenLet", "hscript doesn't support pattern-matching");
        disableMacro(copy, "unlessLet", "hscript doesn't support pattern-matching");

        copy.macros["cast"] = (wholeExp:ReaderExp, exps, k) -> {
            exps[0];
        };

        return copy;
    }

    public static function forMacroEval(k:KissState): KissState {
        var copy = k.forHScript();
        // Catch accidental misuse of (set) on macroVars
        var setLocal = copy.specialForms["set"];
        copy.specialForms["set"] = (wholeExp:ReaderExp, exps, k:KissState) -> {
            switch (exps[0].def) {
                case Symbol(varName) if (k.macroVars.exists(varName)):
                    var b = wholeExp.expBuilder();
                    // have this throw during macroEXPANSION, not before (so assertThrows will catch it)
                    copy.convert(b.throwKissError('If you intend to change macroVar $varName, use setMacroVar instead. If not, rename your local variable for clarity.'));
                default:
                    setLocal(wholeExp, exps, copy);
            };
        };

        // TODO should this also be in forHScript()?
        // In macro evaluation,  
        copy.macros.remove("eval");

        return copy;
    }

    // Return an identical Kiss State, but without wrapping list expressions as kiss.List constructor calls.
    public static function withoutListWrapping(k:KissState) {
        var copy = new Cloner().clone(k);
        copy.wrapListExps = false;
        return copy;
    }

    // Return an identical Kiss State, but prepared for parsing a branch pattern of a (case...) expression
    public static function forCaseParsing(k:KissState):KissState {
        var copy = withoutListWrapping(k);
        copy.macros.remove("or");
        copy.specialForms["or"] = SpecialForms.caseOr;
        copy.specialForms["as"] = SpecialForms.caseAs;
        return copy;
    }

    public static function convert(k:KissState, exp:ReaderExp) {
        return readerExpToHaxeExpr(exp, k);
    }
    #end
}

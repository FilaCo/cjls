
## cangjieJSON


### 介绍
cangjieJSON是一款将仓颉对象和json字符串之间序列化和反序列化的库


- `@JsonAdapter`修饰的类或结构体，必须要有一个**无参的构造函数**。
- 目前支持修饰 `class`、`struct` 类型，暂不支持 `enum` 类型。

通过提供以下宏，来简化仓颉代码中 JSON 序列化和反序列化的开发：

- 提供 `@JsonAdapter` 宏用于修饰 class/struct，为其自动生成序列化和反序列化的成员方法；
- 提供 `@JsonName["newName"]` 宏用于修饰 class/struct 里的成员，使其在序列化和反序列化过程中使用别名；
- 提供 `@JsonIgnore` 宏用于修饰 class/struct 里的成员，使其不参与序列化和反序列化；
- 提供 `@JsonIgnoreNull` 宏用于修饰 class/struct 里的成员，如果该成员值为 None，则不进行序列化；反序列化仍然正常执行。
- 提供 `@JsonDefault` 宏用于修饰 class/struct 里的成员，在反序列化的时候，如果json字符串中不存在该字段，则保持默认值。
- 提供 `AnyType` 类型，用于表示任意可能的 JSON 类型（bool、int、float、string、array、object、null）。

同时对外暴露了如下接口：
- `IJsonAdapter<T>` 接口：序列化和反序列化的接口，使用 `@JsonAdapter` 修饰的 class/struct 默认都实现了该接口；
- `JsonTypeMismatch` 异常类：在反序列化时，如果JSON的数据类型与 class/struct 成员的类型不一致，会抛出该异常；
- `JsonFieldNotExist` 异常类：在反序列化时，如果 class/struct 的成员变量名字，在 JSON 字符串中找不到对应的 key，会抛出该异常。
- `JsonGetValueException` 异常类，调用 `AnyType` 的 `getValue<T>()` 方法时，如果类型不匹配，会抛出该异常。
- `IJsonValueExtend` 接口：为 `JsonValue` 类型提供了一些扩展，更方便地访问 json 对象。

### 1 核心方法介绍

```cangjie

    /**
     * 将json字符串反序列化为Basic对象
     * 
     * 参数 str - json字符串
     *
     * 返回值 Basic - 被@JsonAdapter修饰的Class或Struct
     */
    public static func fromJson(str: String): Basic

    /**
     * 将Basic对象序列化为Json字符串
     * 
     * 返回值 String - 序列化后的json字符串
     */
    public func toJson(): String


    /**
     * 将JsonValue对象转化为Basic对象
     * 
     * 参数 jsonValue - JsonValue对象
     *
     * 返回值 Basic - 被@JsonAdapter修饰的Class或Struct
     */
    public static func fromJsonValue(jsonValue: JsonValue): Basic

    /**
     * 将Basic对象转化为JsonValue对象
     * 
     * 返回值 JsonValue - 转化后的JsonValue对象
     */
    public func toJsonValue(): JsonValue

```

### 2 cangjieJSON宏介绍

### 2.1 `@JsonAdapter` 宏

用于修饰 class、struct 类型（支持泛型），使其实现 `IJsonAdapter<T>` 接口，`IJsonAdapter<T>`的接口定义如下：

```cangjie
public interface IJsonAdapter<T> {
    static func fromJson(str: String): T {
        fromJsonValue(JsonValue.fromStr(str))
    }

    static func fromJsonValue(jsonValue: JsonValue): T

    func toJson(): String {
        toJsonValue().toString()
    }

    func toJsonValue(): JsonValue
}
```

示例如下：

```cangjie
@JsonAdapter
public class Basic {
    public var a: Int64 = 0
    public var b: String = ""
    public var c: ?String = None
    public var d: Array<Int64> = Array<Int64>()
    public var e: ArrayList<String> = ArrayList<String>()
    public var f: HashMap<String, Int64> = HashMap<String, Int64>()

    // other member functions
}
```

宏展开之后，对应的代码为：

```cangjie
public class Basic <: IJsonAdapter <Basic> {
    public var a: Int64 = 0
    public var b: String = ""
    public var c: ?String = None
    public var d: Array<Int64> = Array<Int64>()
    public var e: ArrayList<String> = ArrayList<String>()
    public var f: HashMap<String, Int64> = HashMap<String, Int64>()

    // other member functions

    public static func fromJsonValue(jsonValue: JsonValue): Basic {
        ...
    }

    public func toJsonValue(): JsonValue {
        ...
    }

    public static func fromJson(str: String): Basic {
        ...
    }

    public func toJson(): String {
        ...
    }
}
```

因此开发者可以通过调用以上方法来进行 JSON 的序列化和反序列化：

```cangjie
let input: String = #"{"a":123,"b":"bbbbb","c":null,"d":[1,2,3],"e":["s1","s2","s3"],"f":{"f1":123,"f2":456}}"#

// 反序列化为仓颉对象
let b = Basic.fromJson(input)

// 序列化为 JSON 字符串
println(b.toJson())
```

> **注意**
>
> 以下类型均已默认实现了 `IJsonAdapter` 接口，可以直接使用：
>
>   - 基础类型：`Int8/16/32/64`、`UInt8/16/32/64`、`Float16/32/64`、`Bool`、`String`
>   - 可空类型：`Option<T>`
>   - 集合类型：`Array<T>`、`ArrayList<T>`、`HashSet<T>`、`HashMap<String, V>`
>
> 以上泛型参数需要满足 `IJsonAdapter` 接口约束。

#### 2.1.1 `withSuperClass` 属性

`@JsonAdapter` 修饰的 class 在默认情况下，**只能针对自身的成员变量进行序列化和反序列化，并不包含其父类里的成员变量**。

在子类的序列化和反序列化的过程中，为了使其包含父类的成员变量，`@JsonAdapter` 支持一个可选的 `withSuperClass` 属性，用于指定其父类类型。

> 注意：
>
> - 在这种情况下，父类也必须使用 `@JsonAdapter` 修饰。
> - `@JsonAdapter` 修饰 struct 类型时，不支持 `withSuperClass` 属性。

示例如下：

```cangjie
// 如果需要被继承，需要添加 open 访问修饰符。
@JsonAdapter
public open class Parent {
    public var a: Int64 = 0
}

// 指定父类类型为 Parent，表明父类的成员也将被序列化和反序列化。
@JsonAdapter[withSuperClass = Parent]
public class Child <: Parent {
    public var b: String = ""
}

main() {
    let input = #"{"a":123,"b":"hello"}"#

    let c: Child = Child.fromJson(input)
    println(c.a) // 输出 123
    println(c.b) // 输出 hello
}
```

#### 2.1.2 `withGenericType` 属性

实际上，`@JsonAdapter` 可以用于修饰一个泛型类或泛型结构体，但是**该泛型类型不能参与序列化和反序列化的过程**（比如，@JsonIgnore 修饰的成员变量的类型可以使用该泛型类型）。

如果泛型类型需要参与序列化和反序列化的过程，`@JsonAdapter` 提供了一个可选的 `withGenericType` 属性用于指定其泛型变元。

> 注意：
>
> 1. `withGenericType` 目前最多支持 1 个泛型变元。
> 2. `withGenericType` 指定的泛型变元，会自动添加 `where T <: IJsonAdapter<T>` 的泛型约束。

示例如下：

```cangjie
@JsonAdapter
public class MyData {
    public var a: Int64 = 0
    public var b: String = ""
}

// 指定泛型变元 T，支持类型为 T 的成员参与序列化和反序列化，并自动为其添加 IJsonAdapter<T> 泛型约束。
@JsonAdapter[withGenericType = T]
public class Result<T> {
    public var data: ?T = None
}

main() {
    let input = #"{"data":{"a":123,"b":"hello"}}"#
    let res = Result<MyData>.fromJson(input)
    println(res.toJson()) // 输出：{"data":{"a":123,"b":"hello"}}
}
```

#### 2.1.3 `allowNull` 属性

在反序列化的时候，当不确定 JSON 字符串中哪些字段可能不存在、或者值为 null，又不希望 class/struct 的成员变量都使用 `Option<T>` 类型来表示，那么可以在 `@JsonAdaptor` 宏中使用 `allowNull` 属性，当输入的 JSON 字符串中字段不存在或者值为null时，class/struct 里的成员变量保持初始默认值，不会抛出异常。

示例如下：

```cangjie
@JsonAdapter[allowNull]
public class AllowNullClass {
    public var a: String = "default"
    public var b: String = "default"
    public var c: String = ""
}

main() {
    // 其中字段 a 缺失，字段 b 为 null。
    let input = #"{
        "b": null,
        "c": "ccc"
    }"#

    let obj = AllowNullClass.fromJson(input)
    println(obj.a)  // 输出：default
    println(obj.b)  // 输出：default
    println(obj.c)  // 输出：ccc
}
```

#### 2.1.4 `@JsonName` 宏

用于修饰 class 或 struct 里的成员，使其在序列化和反序列化过程中使用新的名字。例如：

```cangjie
@JsonAdapter
public class JsonNameExample {
    @JsonName["newName"]
    public var name: String = ""
}

main() {
    let input = #"{"name": "123"}"#
    JsonNameExample.fromJson(input) // 会抛出 JsonFieldNotExist 异常：'JsonNameExample.newName' not exist


    let input2 = #"{"newName": "123"}"#
    println(JsonNameExample.fromJson(input2).toJson()) // 正常
}
```

#### 2.1.5 `@JsonIgnore` 宏

用于修饰 class 或 struct 里的成员，使其不参与序列化和反序列化。例如：

```cangjie
// IgnoreClass 没有使用 @JsonAdapter 修饰
public class IgnoreClass {
    public var str = ""
    public var val = 123
}

@JsonAdapter
public class JsonIgnoreExample {
    // 使用 @JsonIgnore 修饰的成员将不参与序列化和反序列化
    @JsonIgnore
    public var a: Int64 = 0

    // static 成员必须使用 @JsonIgnore 修饰
    @JsonIgnore
    public static var sa: Int64 = 0

    // private 成员必须使用 @JsonIgnore 修饰
    @JsonIgnore
    private var pa: Int64 = 0

    // 使用 @JsonIgnore 修饰的成员，其类型无需满足 IJsonAdapter 接口约束
    @JsonIgnore
    public var b: IgnoreClass = IgnoreClass()  

    public var c: Int64 = 0
}

main() {
    let input = #"
    {
        "a": 1,
        "sa": 2,
        "pa": 3,
        "b": {
            "str": "sss",
            "val":456
        },
        "c":789
    }"#
    println(JsonIgnoreExample.fromJson(input).toJson()) // 输出：{"c":789}
}
```

#### 2.1.6 `@JsonIgnoreNull` 宏

用于修饰 class 或 struct 里的成员，如果该成员值为 None，则不进行序列化；反序列化仍然正常执行。例如：

```cangjie
@JsonAdapter
public class IgnoreNullExample {
    // @JsonIgnoreNull 可以用于修饰非Option类型的成员，但是不会有效果
    @JsonIgnoreNull
    public var a: Int64 = 0

    @JsonIgnoreNull
    public var b: Option<Int64> = 0

    @JsonIgnoreNull
    public var c: Option<String> = ""

    @JsonIgnoreNull
    public var d: Option<ArrayList<Int64>> = None

    @JsonIgnoreNull
    public var e: Option<ArrayList<String>> = None
}

main() {
    // 如果 JSON 字符串中的值为 null，经过反序列化后，再序列化时该字段会被忽略
    let input = #"{"a":1,"b":null,"c":"ccc","d":[4,5,6],"e":null}"#
    let expectOutput = #"{"a":1,"c":"ccc","d":[4,5,6]}"#
    println("input  = " + input)
    println("expect = " + expectOutput)
    println("actual = " + IgnoreNullExample.fromJson(input).toJson())

    // 如果 JSON 字符串中没有对应的字段，经过反序列化后，再序列化时该字段会被忽略
    let input2 = #"{"a":1}"#
    let expectOutput2 = #"{"a":1}"#
    println("input  = " + input2)
    println("expect = " + expectOutput2)
    println("actual = " + IgnoreNullExample.fromJson(input2).toJson())
}
```

#### 2.1.7 `@JsonDefault` 宏

用于修饰 class 或 struct 里的成员，如果 json 字符串中没有提供对应的字段，则反序列化时保持默认值。例如：

```cangjie
@JsonAdapter
public class Example {
    @JsonDefault
    public var a: String = "default"
}

main() {
    // 如下 json 字符串没有字段 a
    let input = #"{}"#
    let obj = Example.fromJson(input)
    println(obj.a) // 打印: default

    // 如下 json 字符串中有字段 a
    let input2 = #"{"a":"aaa"}"#
    let obj2 = Example.fromJson(input2)
    println(obj2.a) // 打印：aaa
}
```

### 2.2 AnyType 类型

`AnyType` 可用于表示任意可能的 JSON 类型（bool、int、float、string、array、object、null）。其接口定义如下：

```cangjie
public class AnyType <: IJsonAdapter<AnyType> {
    // 原始的 JsonValue 值。
    public var jsonValue: JsonValue

    public init()
    public init(value: JsonValue)

    // 判断 AnyType 的类型
    public func isArray(): Bool
    public func isBool(): Bool
    public func isFloat(): Bool
    public func isInt(): Bool
    public func isNull(): Bool
    public func isObject(): Bool
    public func isString(): Bool

    // 转换为对应的 T 类型，如果类型不匹配，会抛出异常。
    public func getValue<T>(): T where T <: IJsonAdapter<T>

    // 实现 IJsonAdapter 接口
    public static func fromJsonValue(value: JsonValue): AnyType
    public func toJsonValue(): JsonValue
}
```

具体使用示例可参考[单元测试用例源码](../src/test/AnyType_test.cj)

### 2.3 JsonValue 扩展

为了更加方便的使用 JsonValue 类型，为其扩展了如下接口：

```cangjie
// 扩展JsonValue
public interface IJsonValueExtend {
    // 判断JsonValue的类型
    func isBool(): Bool
    func isInt(): Bool
    func isFloat(): Bool
    func isString(): Bool
    func isObject(): Bool
    func isArray(): Bool
    func isNull(): Bool

    // 为JSON Object类型提供一系列简易的set方法，如果当前不是JSON Object类型，则写入失败，返回false。
    func setBoolValue(key: String, value: Bool): Bool
    func setIntValue(key: String, value: Int64): Bool
    func setFloatValue(key: String, value: Float64): Bool
    func setStringValue(key: String, value: String): Bool
    func setObjectValue(key: String, value: JsonObject): Bool
    func setArrayValue(key: String, value: Array<JsonValue>): Bool
    func setNullValue(key: String): Bool
    func setJsonValue(key: String, value: JsonValue): Bool

    // 为JSON Object类型提供一系列简易的get方法，如果当前不是JSON Object类型，返回default默认值。
    func getBoolValue(key: String, default!: Bool, onException!: (Exception) -> Unit): Bool
    func getIntValue(key: String, default!: Int64, onException!: (Exception) -> Unit): Int64
    func getFloatValue(key: String, default!: Float64, onException!: (Exception) -> Unit): Float64
    func getStringValue(key: String, default!: String, onException!: (Exception) -> Unit): String
    func getArrayValue(key: String, default!: Array<JsonValue>, onException!: (Exception) -> Unit): Array<JsonValue>
    func getJsonObject(key: String, default!: JsonObject, onException!: (Exception) -> Unit): JsonObject
    func getJsonValue(key: String, default!: JsonValue, onException!: (Exception) -> Unit): JsonValue
}
```



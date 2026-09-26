# tag_v1.0.0 (2025-11-08)
  适配cjc1.0.3
  文档修改并且增加用例

# tag_v0.1.3 (2025-07-27)

【新增】`@JsonAdaptor` 新增支持属性 `allowNull`，当输入的 JSON 字符串中未提供某个字段、或者字段值为 null 时，则反序列化时 class/struct 对应的成员保持为初始默认值，不会抛出异常。

# tag_v0.1.2 (2025-06-24)

【新增】新增 `@JsonDefault` 宏

# tag_v0.1.1 (2025-05-27)

【新增】宏支持 struct 类型

# tag_v0.1.0 (2025-05-27)

> 注意：为了提升序列化与反序列化性能，移除对 seiralization 模块的依赖，本版本存在接口变更。

- 【修改】`IJsonAdapter` 不再继承 `Serializable<T>` 接口，因此，
    - 删除了 `func serialize(): DataModel` 和 `static func deserialize(dm: DataModel): T` 两个接口；
    - 新增了 `func toJsonValue(): JsonValue` 和 ` static func fromJsonValue(jsonValue: JsonValue): T` 两个接口；
    - 原有的 `func toJson(): String` 和 `static func fromJson(str: String): T` 两个接口保持不变。
- 【修改】`Int64`/`Int32`/...、`UInt64`/...、`Array`/`ArrayList`/`HashSet`/`HashMap`、`AnyType` 等基本类型均重新实现 `IJsonAdapter` 接口。
- 【修改】修改了 `JsonTypeMismatch` 异常类的构造函数
- 【修改】现在 private 成员变量也可以参与序列化和反序列化，不用强制加 `@JsonIgnore` 宏。
- 【删除】不再支持 `Rune` 类型
- 【新增】扩展 `JsonKind` 类型，新增 `toString`、`==`、`!=` 三个方法。
- 【新增】扩展 `JsonValue` 类型，提供常用的类型判断、读写JSON对象的功能。
- 【修复】修复社区反馈的 String 类型序列化再反序列化失败的问题。

# tag_v0.0.3 (2025-03-19)

- 【新增】新增一个 `class AnyType` 类型（实现了 `IJsonAdapter` 接口），用于支持任意 JSON 类型（bool、int、float、string、array、object、null），并提供 `getValue<T>()` 泛型方法便于转换为具体类型的值。
- 【新增】新增一个 `JsonGetValueException` 异常类，在调用 `AnyType` 对象的 `getValue<T>()` 方法时，如果类型不匹配，会抛出该异常。

# tag_v0.0.2（2025-03-09）

【新增】为 `@JsonAdapter` 宏新增2个属性：

- `withSuperClass = Xxx`：用于支持子类在进行 JSON 序列化和反序列化时，将父类（比如 `Xxx`）的成员变量也进行序列化和反序列化。
- `withGenericType = T`：用于给指定的泛型变元（比如 `T`）添加 `where T <: IJsonAdapter<T>` 泛型约束，以支持泛型类型的成员也可以自动进行 JSON 序列化和反序列化。

# tag_v0.0.1（2024-12-23）

首版本，通过提供以下宏，来简化仓颉代码中 JSON 序列化和反序列化的开发：

- 提供 `@JsonAdapter` 宏用于修饰 class，为其自动生成序列化和反序列化的成员方法；
- 提供 `@JsonName["newName"]` 宏用于修饰 class 里的成员，使其在序列化和反序列化过程中使用别名；
- 提供 `@JsonIgnore` 宏用于修饰 class 里的成员，使其不参与序列化和反序列化；
- 提供 `@JsonIgnoreNull` 宏用于修饰 class 里的成员，如果该成员值为 None，则不进行序列化；反序列化仍然正常执行。

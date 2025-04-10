#import "../lib.typ":*

= 可扩展的查询优化器
构建一个可以扩展的查询优化器的方式之一是拥有一组可以扩展的_规则_，这个规则用于定义所有等效的计划的空间。正如@介绍\中所提及的，这种方法以逻辑算子、物理算子以及一系列的_转换（transformation）_和_实现规则（implementation
rules）_的概念为中心。优化器在_搜索策略（search
strategy）_的指导下，按照一定的顺序应用规则（rules），在等效的计划空间内探索，并且在众多备选计划空间中选择一个高效的计划。

在这一章中，我们首先介绍一个扩展的优化器的概念（@可扩展的查询优化器基本概念）。然后我们深入讨论两个可以扩展的优化器框架：Volcano框架以及Cascades框架。我们从介绍Volcano以及其搜索开始（@volcano）,然后我们简单的看下Volcano的局限性，正因其局限性，催生了其后来者，Cascades框架（@cascades）。我们介绍了在实践中用于提高Volcano和Cascades效率的其他优化以及启发式方法（@提高查询效率的技术）。为了说明可扩展的查询优化器如何轻松的将新功能合并高查询处理中，我们介绍了Microsoft
SQL Server的优化器是如何利用/*TODO*/来实现列存的（@Microsoft-SQL-Server的扩展性示例）。在本章的最后，我们将介绍可扩展的查询优化器是如何生成多核并行以及分布式的查询（@并行分布式查询流程）。

== 基本概念<可扩展的查询优化器基本概念>

我们在基于规则的（rule-based）的可扩展优化器（例如Volcano以及Cascades。）中介绍了一些重要的概念。但是需要注意，这些概念（例如：算子operators、属性properties）并不是Volcano/Cascades中所独有的概念，它们被用于System
R、Starburst以及EXODUS等系统的查询优化器中。

看一下@query2，其相应的逻辑以及物理计划在@query2的逻辑以及物理计划\中。

#sql-code()[
```sql
SELECT *
FROM A, B
WHERE A.k = B.k
```
]<query2>

#picture-figure("", image("../pic/query2的逻辑以及物理计划.png"))<query2的逻辑以及物理计划>

*逻辑以及物理算子* 逻辑算子定义了一个或者多个关系的关系操作，例如在@query2的逻辑以及物理计划\中A和B之间的Join运算符。这里有一点需要注意，在查询优化器中，可能会引入非关系的逻辑算子，例如`Apply`。`Apply`用来处理子查询（@使用Apply代数表示子查询）以及用于处理并行性的交换操作（@多核并行）。因此使用逻辑算子的集合以及由此产生的优化器的搜索空间，超过了SQL查询中所呈现的范围。物理算子是一种算法的实现，用于执行在查询执行中所需的操作。物理算子的一个例子是`Hash Join`（@query2的逻辑以及物理计划）。注意，一个逻辑算子可以由不同的物理算子来实现，反之亦然。例如，逻辑算子`Join`可以由`Hash Join`和`Nested Loops Join`来实现。类似，物理算子`Hash Join`可以用于实现多种逻辑算子，例如`Join`、`Left Outer Join`以及`Union`。此外，一个逻辑算子可以由多个物理算子来实现。例如我们在
@inner-join转换\将会介绍的逻辑算子`Inner Join`，该算子一个通过`Sort`以及`Merge Join`算子来实现。

*逻辑以及物理表达式* 一个逻辑表达式是由逻辑算子构成的树状结构。它代表着一个关系代数表达式。例如@query2\中的连接操作就可以使用$L_1: A join B$表示，也正如@query2的逻辑以及物理计划\所表示的一样。一个物理表达式是一个由物理算子构成的树状结构，它也被成为_物理计划（physical
plan）_或者简称为_计划（plan）_。例如表达式$P_1:italic("HashJoin(TableScan(A), TableScan(B))")$表示的就是@query2的逻辑以及物理计划\中的$L_1$实现。

*逻辑以及物理属性*

== Volcano<volcano>

=== 简介
=== 查询

#algorithm-code(
  [
  在Volcano优化器中查询，在`GenerateLogicalExpr`、`MatchTransRule`、`UpdatePlan`这几个操作中，_备忘录（Mono）_中的组和表达式会被更新。随着搜索结果的推进，表达式的成本的限制也会被更新。在`FindBestPlan`操作结束以后，搜索得到的缓存结果会被添加到Mono中。
  ],
)[
  + function GenerateLogicalExpr$italic("(LogExpr, Rules)")$ #sym.triangle.stroked.r
    + for $italic("Child")$ in inputs of $italic("LogExpr")$
      + if $italic("Group(Child)") in.not italic("Memo")$ then
        + $italic("GererateLogicalExpr(Child)")$
    + $italic("MatchTransRules(LogExpr, Rules)")$

  + function MatchTransRule$italic("LogExpr, Rules")$
    + for $italic("rule")$ in $italic("Rules")$ do
      + if $italic("rule")$ matches $italic("LogExpr")$ then
        + $italic("NewLogExpr") arrow.l italic("Transform(LogExpr, rule)")$ #sym.triangle.stroked.r 更新memo并且记录其邻居
        + $italic("GenerateLogicalExpr(NewLogExpr)")$ 
        + #sym.triangle.stroked.r 只会在$italic("NewLogExpr")$在memo中不存在的时候才会执行
]
=== 自定义查询策略
=== 添加新的规则以及运算符
== Cascades<cascades>
=== Cascades的主要改进
=== 查询简介
=== 查询算法
=== Cascades中的查询优化示例
== 提高查询效率的技术<提高查询效率的技术>
== Microsoft SQL Server的扩展性示例<Microsoft-SQL-Server的扩展性示例>
== 并行分布式查询流程<并行分布式查询流程>
=== 多核并行<多核并行>
=== 分布式查询优化
== 建议阅读
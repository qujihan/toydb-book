#import "../../lib.typ": *

#code-figure(
  // "tree src/raft",
  "Raft算法",
  ```zsh
    src/raft
    ├── log.rs # 定义了Raft中的Log
    ├── message.rs # 定义了Raft中Node之间交互的信息
    ├── mod.rs
    ├── node.rs # 定义了Node(Leader, Follower, Candidate)以及其行为
    ├── state.rs # 定义了Raft中的状态机
    └── testscripts
        └── ...
    ```,
)

== Raft介绍
Raft共识算法是一种分布式一致性算法，它的设计目标是提供一种易于理解的一致性算法。Raft算法分为三个部分：领导选举、日志复制和安全性。具体的实现可以参考Raft论文#footnote("Raft Paper：" + link("https://raft.github.io/raft.pdf")) #footnote("Raft Thesis：" + link("https://web.stanford.edu/~ouster/cgi-bin/papers/OngaroPhD.pdf")) #footnote("Raft 官网：" + link("https://raft.github.io"))。

Raft有三个特点：
+ 线性一致性（强一致性）：一旦一个数据被Client提交，那么所有的Client都能读到这个数据。（就是永远看不到过时的数据）
+ 容错性：知道大多数节点在运行，就可以保证系统正常运行。
+ 持久性：只要大多数节点在运行，那么写入就不会丢失。

Raft算法通过选举一个Leader来完成Client的请求以及将数据复制到其他节点。请求一旦被大多数节点所确认后就会执行。如果Leader挂了，那么会重新选举一个Leader。在一个集群中，需要至少有三个节点来保证系统的正常运行。

有一点需要说明，Raft并不提供水平扩展。当Client有一个请求时，只能由单一的Leader来处理，这个Leader很快就会称为系统的瓶颈。而且每一个节点会存储整个数据集完整的副本。

系统通常会将数据分片到多个Raft集群中，并在它们之间使用分布式事务协议来处理这个问题。不过与现在的这一章关系不大。

=== Raft中日志与状态机

Raft维护了Client提交的任意写命令的有序Log。Raft通过将Log复制到大多数节点来达成共识。如果能共识成功，就认为Log是已经提交的，并且在提交之前的Log都是不可变的。

当Log已经提交以后，Raft就可以将Log中存储的命令应用到节点本地的状态机。每个Log中包含了index、term以及命令。

- index： Log的索引，表示这个entry在Log中的位置。
- term：当前entry被Leader创建的时候的任期。
- 命令：会被应用在状态机的命令。

注意，_通过index和term可以*确定*一个entry_。

#table-figure("Log可视化")[
#show raw.where(block: false): it => {
  it
}
#table(
  columns: 3,
  stroke: none,
  table.hline(),
  table.header([Index], [Term], [Command(命令)]),
  table.hline(stroke: 0.5pt),
  [1],
  [1],
  [`None`],
  [2],
  [1],
  [`CREATE TABLE table (id INT PRIMARY KEY, value STRING)`],
  [3],
  [1],
  [`INSERT INTO table VALUES (1, "foo")`],
  [4],
  [2],
  [`None`],
  [5],
  [2],
  [`UPDATE table SET value = 'bar' WHERE id = 1`],
  [6],
  [2],
  [`DELETE FROM table WHERE id = 1`],
  table.hline(),
)
]<log_example>

状态机必须是确定的，只有这样，才能所有的节点达到相同的状态。Raft将会在所有节点上独立的，以相同的顺序应用相同的命令。但是如果命令具有非确定性行为（比如随机数生成、与外部通信），会产生分歧。

=== Leader选举

在Raft中，每一个节点都处于三个身份中的一个：
+ Leader：处理所有的Client请求，以及将Log复制到其他节点。
+ Follower：只是简单的响应Leader的请求。可能并不知道Leader是谁。
+ Candidate：在想要选举Leader时，节点会变成Candidate。

Raft算法都依赖一个单一的保证：在任何时候都只能有一个有效的Leader（旧的、已经被替换掉的可能仍然认为自己是Leader，但是不起作用）。Raft通过领导者选举机制来强制保证这一点。

Raft将时间划分为term，term与时间一样，是一个严格单调递增的值。在一个term内只能有一个Leader，而且不会改变。每一个节点会存储当前已知的最后term。并且在节点直接发送信息的时候会附带当前term（如果收到大于当前term的会变成Follower，收到小于当前term的会忽略）。

可以把在Leader选举过程分成两个部分：
+ 谁想成为Leader
+ 如何给想成为Leader的Node投票

如果Follower在选举超时时间内没有收到Leader的心跳信息，会变成Candidate并且开始选举Leader。如果一个节点与Leader失联（可能是网络环境等原因），那么他会不断的自行选举，直到网络恢复。因为他不断的自行选举，他的term会变得非常大，一旦恢复以后会大于集群中的其他节点，此时会在其任期内进行选举，也就是扰乱了当前的领导者（本来集群正常运行，每一个突然收到了特别大的term信息的节点，都会变成Follower，然后整个集群被迫重新开始选举），为了解决这个问题，提出了PreVote（Raft+

每个节点刚开始的时候都是Follower，并且都是不知道谁是Leader。如果收到来自当前或者更大term的Leader发来的信息，会变成知道Leader是谁的Follower。否则，在等待一段时间（根据定义的选举超时时间）后，会变成Candidate并且开始选举Leader。

Candidate会将自己的term号+1，并且向其他节点发送投票请求。收到请问投票的信息后，节点开始相应投票。每个节点只能投一次票，先到先得，并且有一个隐藏的语义是：Candidate会投给自己一票。

当Candidate收到大多数节点（>50%）的投票后，就会变成Leader。然后向其他节点发送心跳信息，以断言并且保持自己的Leader身份。所有节点在收到Leader的心跳信息后，会变成Follower（无论当时投票给了谁）。Leader还会定期发送心跳信息，以保持自己的Leader身份，新Leader还会一个空item，以便安全提前前面term的item（Raft
paper 5.4.2）。

有成功就会有失败，可能因为平局或者多数节点失联，在选举超时时间内没有选出Leader。这时候会重新开始选举（term+1），直到选出Leader。

为了避免多次平局，Raft引入了随机化的选举超时时间。这样可以避免多个节点在同一时间内开始选举（Raft paper 5.2）。

如果Follower在选举超时时间内没有收到Leader的心跳信息，会变成Candidate并且开始选举Leader。如果一个节点与Leader失联（可能是网络环境等原因），那么他会不断的自行选举，直到网络恢复。因为他不断的自行选举，他的term会变得非常大，一旦恢复以后会大于集群中的其他节点，此时会在其任期内进行选举，也就是扰乱了当前的领导者（本来集群正常运行，每一个突然收到了特别大的term信息的节点，都会变成Follower，然后整个集群被迫重新开始选举），为了解决这个问题，提出了PreVote（Raft
thesis 4.2.3）。不过这就属于Raft的优化问题了，会在我的另外一本书中讨论。

=== 日志复制与共识

当Leader收到了来自Client的写请求的时候，会将这个请求追加到其本地的Log中，然后将这个请求发送给其他节点。其他节点会尝试将收到的item也追加到自己的Log中，并且向Leader发送相应信息。

一旦大多数节点确认了追加操作，Leader就会提交提交这个item，并且应用到本地状态机，然后将结果返回给Client。

然后在下一个心跳的时候，告诉其他节点这个item已经提交了，其他节点也会将这个item提交并且应用到本地状态机。关于这个的正确性不是必须的（因为其成为Leader，它们也会提交并且应用该item，否则也没必要应用它）。

Follower也有可能比不会应用这个item，可能因为落后于Leader、日志出现了分歧等（Raft paper 5.3节）等情况。

Leader发送给其他Node的Append中包含了item的index以及term，index+term（如@log_example
所示），如果两个item拥有相同的index+term，那么这两个item是相同的，并且之前的item也是相同的（Raft Paper 5.3）。

如果Follower收到了index+term不匹配的item，会拒绝这个item。当Leader收到了拒绝信息，会尝试找一个与Follower的日志相同的点，然后将这个点之后的item发送给Follower。这样可以保证Follower的日志与Leader的日志相同。

Leader会通过发送一个只包含index+term的信息来探测这一点，也就是逐个较小index来探测，直到Follower相应匹配。然后发送这个点之后的item（Raft
paper 5.3）。

Leader的心跳信息也会包含last_index以及term，如果Follower的日志落后于Leader，会在给心跳的返回信息中说明，Leader会像上面一样发送日志。

=== Client 的请求

Client会将请求提交给本地的Raft节点。但是就像上面提到的，它们仅仅在Leader上处理，所以Followers会将请求转发给Leader（Raft
thesis 6.2）。

关于写请求，会被Leader追加到Log中，然后发送给其他节点。一旦大多数节点确认了这个请求，Leader就会提交这个请求，并且应用到本地状态机。一旦应用到状态机中，Leader会通过日志查找的写请求的结果，并且返回给Client。确定性的错误（外键违规）会返回给客户端，非确定性的错误（IO错位）会直接使节点崩溃（这样就可以避免副本状态产生分歧）。

关于读请求，仅在Leader上处理，不需要Raft的日志的复制。但是为了确保强一致性，Leader会在处理读请求的时候，会通过一次心跳来避免脏读（避免其他地方选举出来了新的Leader而导致的Leader身份失效）。一旦可以确认Leader的身份，Leader就会将读取结果返回给Client。
#import "../../lib.typ": *
== Raft之Message

#code-figure(
  // "src/raft/message.rs",
  "Message 类型",
)[
```rust
  /// 发送者和接收者的消息信封(在Message上包装了一层额外信息).
  #[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
  pub struct Envelope {
      pub from: NodeID,     // 从哪里来
      pub term: Term,       // 发送者的当前term
      pub to: NodeID,       // 到哪里去
      pub message: Message, // 具体发送的信息
  }

  /// Raft的Node之间的消息, 消息是异步发送的, 可能会丢失或者重排序.
  /// 在实践中, 它们通过TCP连接发送, 并通过crossbeam通道确保消息不会丢失或重排序, 前提是连接保持完好.
  /// 消息的发送以及回执都是通过单独的TCP连接.
  #[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
  pub enum Message {
      /// Candidates 从其他Node中获取投票, 以便成为Leader.
      /// 只有当Candidate的日志至少与投票者一样新时, 才会授予投票.
      Campaign {
          last_index: Index, // Candidate最后一个日志的index
          last_term: Term,   // Candidate最后一个日志的term
      },

      /// Followers 只有在Candidate的日志至少与自己一样新时, 才会投票.
      /// Canidate会隐式的投票给自己.
      CampaignResponse {
          /// true表示投票给Candidate, false表示拒绝投票.
          /// 拒绝投票不是必须的, 但是为了清晰起见, 还是会发送.
          vote: bool,
      },

      /// Leader 会定期发送心跳, 这样有几个目的:
      /// 1. 通知节点当前的 Leader, 防止选举.
      /// 2. 检测丢失的 appends和 reads, 作为重试机制.
      /// 3. 告知Followers 已经提交的 indexes, 以便他们可以应用 entries.
      /// Raft论文中使用了一个空的AppendEntries RPC来实现心跳, 但是我们选择添加一个以更好的分离心跳消息.
      Heartbeat {
          /// last_index 是 Leader 最后一个日志的index, Term 是Leader 的当前 term.
          /// 因为它在选举成功后会追加一个空的entry. Follower 会将这个与自己的日志进行比较, 以确定是否是最新的.
          last_index: Index,
          /// 表示的是 Leader 的最后一个提交的日志的 index.
          /// Followers 会使用这个来推进他们的 commit index, 并应用 entries.
          /// (只有在本地日志与 last_index 匹配时才能安全地提交这个).
          commit_index: Index,
          /// Leader在这个term中的最新读序列号.
          read_seq: ReadSequence,
      },

      /// Followers 回应 Leader 的心跳, 以便 Leader 知道自己还是 Leader.
      HeartbeatResponse {
          /// 如果不为0, 表示Follower的日志与Leader的日志匹配, 否则Follower的日志要么是不一致的, 要么是落后于Leader.
          match_index: Index,
          /// 心跳的 读 序列号.
          read_seq: ReadSequence,
      },

      /// Leaders replicate log entries to followers by appending to their logs
      /// after the given base entry.
      ///
      /// If the base entry matches the follower's log then their logs are
      /// identical up to it (see section 5.3 in the Raft paper), and the entries
      /// can be appended -- possibly replacing conflicting entries. Otherwise,
      /// the append is rejected and the leader must retry an earlier base index
      /// until a common base is found.
      ///
      /// Empty appends messages (no entries) are used to probe follower logs for
      /// a common match index in the case of divergent logs, restarted nodes, or
      /// dropped messages. This is typically done by sending probes with a
      /// decrementing base index until a match is found, at which point the
      /// subsequent entries can be sent.
      /// Leaders 复制日志到 Followers, 通过在给定的 base 之后 entry 追加到他们的 log 中.
      Append {
          /// 即将添加的 entry 之前的 entry 的 index
          base_index: Index,
          /// 即将添加的 entry 之前的 entry 的 term
          base_term: Term,
          /// 即将被添加的 entry 集合, index 从 base_index + 1 开始
          entries: Vec<Entry>,
      },

      /// Followers accept or reject appends from the leader depending on whether
      /// the base entry matches their log.
      AppendResponse {
          /// If non-zero, the follower appended entries up to this index. The
          /// entire log up to this index is consistent with the leader. If no
          /// entries were sent (a probe), this will be the matching base index.
          match_index: Index,
          /// If non-zero, the follower rejected an append at this base index
          /// because the base index/term did not match its log. If the follower's
          /// log is shorter than the base index, the reject index will be lowered
          /// to the index after its last local index, to avoid probing each
          /// missing index.
          reject_index: Index,
      },

      /// Leaders need to confirm they are still the leader before serving reads,
      /// to guarantee linearizability in case a different leader has been
      /// estalished elsewhere. Read requests are served once the sequence number
      /// has been confirmed by a quorum.
      Read { seq: ReadSequence },

      /// Followers confirm leadership at the read sequence numbers.
      ReadResponse { seq: ReadSequence },

      /// A client request. This can be submitted to the leader, or to a follower
      /// which will forward it to its leader. If there is no leader, or the
      /// leader or term changes, the request is aborted with an Error::Abort
      /// ClientResponse and the client must retry.
      ClientRequest {
          /// The request ID. Must be globally unique for the request duration.
          id: RequestID,
          /// The request itself.
          request: Request,
      },

      /// A client response.
      ClientResponse {
          /// The ID of the original ClientRequest.
          id: RequestID,
          /// The response, or an error.
          response: Result<Response>,
      },
  }
  ```
]
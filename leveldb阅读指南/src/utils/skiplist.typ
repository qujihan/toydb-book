== 跳表

这部分涉及的代码为：
- `db/skiplist.h`

// #code("Leetcode-1206", "跳表简单实现")[
//   ```cpp
//   #include <random>
//   #include <vector>

//   constexpr int MAX_LEVEL = 32;
//   constexpr double FACTOR = 0.25;

//   struct SkipListNode {
//       explicit SkipListNode(int val, int max_level = MAX_LEVEL) : val(val), forward(max_level, nullptr) {}
//       int val;
//       vector<SkipListNode*> forward;
//   };

//   class Skiplist {
//   public:
//       Skiplist() : head_(new SkipListNode(-1)), level_(0), dis_(0, 1) {}

//       bool Search(int target) {
//           SkipListNode* curr = head_;
//           for (auto i = level_ - 1; i >= 0; i--) {
//               while (curr->forward[i] && curr->forward[i]->val < target) {
//                   curr = curr->forward[i];
//               }
//           }
//           curr = curr->forward[0];
//           return curr && curr->val == target;
//       }

//       void Add(int num) {
//           vector<SkipListNode*> update(MAX_LEVEL, head_);
//           auto curr = head_;
//           for (auto i = level_ - 1; i >= 0; i--) {
//               while (curr->forward[i] && curr->forward[i]->val < num) {
//                   curr = curr->forward[i];
//               }
//               update[i] = curr;
//           }

//           auto new_node_level = getRandomLevel();
//           level_ = max(level_, new_node_level);
//           auto new_node = new SkipListNode(num, new_node_level);
//           for (auto i = 0; i < new_node_level; i++) {
//               new_node->forward[i] = update[i]->forward[i];
//               update[i]->forward[i] = new_node;
//           }
//       }

//       bool Erase(int num) {
//           vector<SkipListNode*> update(MAX_LEVEL, nullptr);
//           auto curr = head_;
//           for (auto i = level_ - 1; i >= 0; i--) {
//               while (curr->forward[i] && curr->forward[i]->val < num) {
//                   curr = curr->forward[i];
//               }
//               update[i] = curr;
//           }
//           curr = curr->forward[0];
//           if (!curr || curr->val != num) {
//               return false;
//           }
//           for (int i = 0; i < level_; i++) {
//               if (update[i]->forward[i] != curr) {
//                   break;
//               }
//               update[i]->forward[i] = curr->forward[i];
//           }
//           delete curr;
//           while (level_ > 1 && head_->forward[level_ - 1] == nullptr) {
//               level_--;
//           }
//           return true;
//       }

//   private:
//       SkipListNode* head_;
//       int level_;
//       uniform_real_distribution<double> dis_;
//       mt19937 gen_{random_device{}()};

//       int getRandomLevel() {
//           int return_level = 1;
//           while (dis_(gen_) < FACTOR && return_level < MAX_LEVEL) {
//               return_level++;
//           }
//           return return_level;
//       }
//   };
//   ```
// ]

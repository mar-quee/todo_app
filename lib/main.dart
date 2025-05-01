import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:todo_app/services/notification_service.dart';
import 'package:flutter/services.dart';

// メイン関数を非同期にして通知の初期化を行う
void main() async {
  // Flutterのウィジェットバインディングを確実に初期化
  WidgetsFlutterBinding.ensureInitialized();

  // macOS向けの設定
  if (Platform.isMacOS) {
    // ステータスバーの色を設定
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
  }

  // 通知サービスを初期化
  final notificationService = NotificationService();
  await notificationService.init();

  // アプリを実行
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TODOアプリ',
      debugShowCheckedModeBanner: false, // デバッグバナーを非表示
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        // macOS向けのUI調整
        visualDensity: VisualDensity.adaptivePlatformDensity,
        brightness: Brightness.light,
        // macOS向けにフォントサイズを調整
        textTheme:
            Platform.isMacOS
                ? Theme.of(
                  context,
                ).textTheme.apply(fontSizeFactor: 1.1, fontSizeDelta: 2.0)
                : null,
      ),
      home: const TodoListScreen(),
    );
  }
}

class TodoListScreen extends StatefulWidget {
  const TodoListScreen({super.key});

  @override
  State<TodoListScreen> createState() => _TodoListScreenState();
}

class _TodoListScreenState extends State<TodoListScreen> {
  // TODOアイテムを保存するリスト
  List<TodoItem> _todoItems = [];
  // 表示用のTODOアイテム（フィルター適用後）
  List<TodoItem> _displayedTodoItems = [];
  // 新しいTODOを入力するためのコントローラー
  final TextEditingController _textController = TextEditingController();
  // ソート方法
  SortMethod _currentSortMethod = SortMethod.createdDate;
  // フィルターするカテゴリー（nullの場合はすべて表示）
  String? _filterCategory;
  // 利用可能なカテゴリーのリスト
  Set<String> _categories = {'仕事', '個人', '買い物', 'その他'};
  // 完了タスクの自動削除の設定（日数、0の場合は削除しない）
  int _completedTasksDeleteDays = 0;
  // 完了タスクを表示するかどうか
  bool _showCompletedTasks = true;
  // 通知サービス
  final NotificationService _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    // 先にユーザー設定を読み込む
    _loadSettings().then((_) {
      // 設定読み込み後にTODOデータを読み込む
      _loadTodos().then((_) {
        // TODOデータ読み込み後に表示/非表示設定を適用
        _applyCompletedTasksVisibility();
      });
      // 完了タスクの自動クリーンアップを実行
      _cleanupCompletedTasks();
    });
    // 通知サービスの初期化
    _initNotifications();
  }

  // 通知サービスの初期化
  Future<void> _initNotifications() async {
    await _notificationService.init();
    // すべてのTODOの通知をスケジュールし直す
    await _notificationService.rescheduleAllNotifications(_todoItems);
  }

  @override
  void dispose() {
    // コントローラーを破棄
    _textController.dispose();
    super.dispose();
  }

  // 保存されたTODOデータを読み込む関数
  Future<void> _loadTodos() async {
    final prefs = await SharedPreferences.getInstance();
    final todosJson = prefs.getStringList('todos') ?? [];

    setState(() {
      _todoItems =
          todosJson
              .map((item) => TodoItem.fromJson(json.decode(item)))
              .toList();

      // カテゴリーリストを更新
      _updateCategories();
    });
  }

  // TODOデータを保存する関数
  Future<void> _saveTodos() async {
    final prefs = await SharedPreferences.getInstance();
    final todosJson =
        _todoItems.map((item) => json.encode(item.toJson())).toList();

    await prefs.setStringList('todos', todosJson);
  }

  // カテゴリーリストを更新する関数
  void _updateCategories() {
    final categoriesFromItems = _todoItems.map((item) => item.category).toSet();
    _categories = {..._categories, ...categoriesFromItems};
  }

  // 新しいTODOを追加する関数
  void _addTodoItem(String task) {
    if (task.isNotEmpty) {
      setState(() {
        _todoItems.add(TodoItem(title: task, completed: false));
        _updateCategories();
        _sortTodos();
        _applyCompletedTasksVisibility();
      });
      _textController.clear();
      _saveTodos();
    }
  }

  // TODOの詳細を編集する画面を表示する関数
  void _editTodoItem(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => TodoEditScreen(
              todo: _todoItems[index],
              categories: _categories,
              onSave: (editedTodo) {
                setState(() {
                  _todoItems[index] = editedTodo;
                  _updateCategories();
                  _sortTodos();
                  _applyCompletedTasksVisibility();
                });
                _saveTodos();
                Navigator.pop(context);
              },
            ),
      ),
    );
  }

  // TODOの完了状態を切り替える関数
  void _toggleTodoItem(int index) {
    setState(() {
      final isNowCompleted = !_todoItems[index].completed;
      _todoItems[index].completed = isNowCompleted;

      // 完了状態になった場合は完了日時を記録、そうでない場合はnullにする
      _todoItems[index].completedDate = isNowCompleted ? DateTime.now() : null;

      _sortTodos();
      // 表示設定を適用（完了タスクの表示/非表示を管理）
      _applyCompletedTasksVisibility();
    });
    _saveTodos();
  }

  // TODOを削除する関数
  void _removeTodoItem(int index) {
    final removedItem = _todoItems[index];
    setState(() {
      _todoItems.removeAt(index);
      _applyCompletedTasksVisibility();
    });
    _saveTodos();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('TODOを削除しました'),
        action: SnackBarAction(
          label: '取り消し',
          onPressed: () {
            setState(() {
              _todoItems.insert(index, removedItem);
              _sortTodos();
              _applyCompletedTasksVisibility();
            });
            _saveTodos();
          },
        ),
      ),
    );
  }

  // TODOをソートする関数
  void _sortTodos() {
    setState(() {
      switch (_currentSortMethod) {
        case SortMethod.createdDate:
          // IDは作成日時のミリ秒をベースにしているので、それでソート
          _todoItems.sort((a, b) => a.id.compareTo(b.id));
          break;
        case SortMethod.dueDate:
          // 期限日でソート（nullは最後に）
          _todoItems.sort((a, b) {
            if (a.dueDate == null && b.dueDate == null) return 0;
            if (a.dueDate == null) return 1;
            if (b.dueDate == null) return -1;
            return a.dueDate!.compareTo(b.dueDate!);
          });
          break;
        case SortMethod.priority:
          // 優先度でソート（高→中→低）
          _todoItems.sort(
            (a, b) => b.priority.index.compareTo(a.priority.index),
          );
          break;
        case SortMethod.category:
          // カテゴリーでソート
          _todoItems.sort((a, b) => a.category.compareTo(b.category));
          break;
      }

      // 完了したタスクは常に下に表示
      final completedItems =
          _todoItems.where((item) => item.completed).toList();
      final nonCompletedItems =
          _todoItems.where((item) => !item.completed).toList();
      _todoItems = [...nonCompletedItems, ...completedItems];
    });
  }

  // 表示するTODOをフィルタリングする関数
  List<TodoItem> _getFilteredTodos() {
    if (_filterCategory == null) {
      return _displayedTodoItems;
    }
    return _displayedTodoItems
        .where((item) => item.category == _filterCategory)
        .toList();
  }

  // ユーザー設定を読み込む関数
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _completedTasksDeleteDays = prefs.getInt('completedTasksDeleteDays') ?? 0;
      _showCompletedTasks = prefs.getBool('showCompletedTasks') ?? true;
    });
  }

  // ユーザー設定を保存する関数
  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('completedTasksDeleteDays', _completedTasksDeleteDays);
    await prefs.setBool('showCompletedTasks', _showCompletedTasks);
  }

  // 完了タスクの自動クリーンアップを実行する関数
  void _cleanupCompletedTasks() {
    if (_completedTasksDeleteDays <= 0) return; // 自動削除が無効な場合は何もしない

    final now = DateTime.now();
    final itemsToKeep =
        _todoItems.where((item) {
          // 完了していないタスクはそのまま残す
          if (!item.completed) return true;

          // 完了日時がnullの場合は残す（古いデータ対応）
          if (item.completedDate == null) return true;

          // 完了してから指定の日数が経過しているかチェック
          final daysSinceCompleted = now.difference(item.completedDate!).inDays;
          return daysSinceCompleted < _completedTasksDeleteDays;
        }).toList();

    // 削除対象のタスクがあれば状態を更新
    if (itemsToKeep.length != _todoItems.length) {
      setState(() {
        _todoItems = itemsToKeep;
      });
      _saveTodos();
    }
  }

  // 完了タスクの表示/非表示設定を適用する
  void _applyCompletedTasksVisibility() {
    setState(() {
      if (!_showCompletedTasks) {
        // 完了タスクを非表示にする（表示用リストのみに影響）
        _displayedTodoItems =
            _todoItems.where((item) => !item.completed).toList();
      } else {
        // すべてのタスクを表示
        _displayedTodoItems = List.from(_todoItems);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final filteredTodos = _getFilteredTodos();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        title: const Text('TODOリスト', style: TextStyle(color: Colors.white)),
        actions: [
          // ソートボタン
          IconButton(
            icon: const Icon(Icons.sort, color: Colors.white),
            onPressed: () {
              _showSortOptions(context);
            },
          ),
          // フィルターボタン
          IconButton(
            icon: const Icon(Icons.filter_list, color: Colors.white),
            onPressed: () {
              _showFilterOptions(context);
            },
          ),
          // 設定ボタン
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () {
              _showSettingsDialog(context);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // カテゴリーフィルターが設定されている場合に表示
          if (_filterCategory != null)
            Container(
              color: Colors.grey[200],
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: Row(
                children: [
                  Text(
                    'フィルター: $_filterCategory',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _filterCategory = null;
                      });
                    },
                    child: const Text('クリア'),
                  ),
                ],
              ),
            ),

          // 新しいTODOを入力するエリア
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      hintText: '新しいTODOを入力...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (value) => _addTodoItem(value),
                  ),
                ),
                const SizedBox(width: 8.0),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _addTodoItem(_textController.text),
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          // TODOリストを表示するエリア
          Expanded(
            child:
                filteredTodos.isEmpty
                    ? const Center(child: Text('TODOがありません。新しいTODOを追加しましょう！'))
                    : ListView.builder(
                      itemCount: filteredTodos.length,
                      itemBuilder: (context, index) {
                        final item = filteredTodos[index];
                        return Dismissible(
                          key: Key(item.id),
                          background: Container(
                            color: Colors.red,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 16.0),
                            child: const Icon(
                              Icons.delete,
                              color: Colors.white,
                            ),
                          ),
                          direction: DismissDirection.endToStart,
                          onDismissed: (direction) {
                            final originalIndex = _todoItems.indexOf(item);
                            _removeTodoItem(originalIndex);
                          },
                          child: Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 8.0,
                              vertical: 4.0,
                            ),
                            child: ListTile(
                              leading: Checkbox(
                                value: item.completed,
                                onChanged: (bool? value) {
                                  final originalIndex = _todoItems.indexOf(
                                    item,
                                  );
                                  _toggleTodoItem(originalIndex);
                                },
                              ),
                              title: Text(
                                item.title,
                                style: TextStyle(
                                  decoration:
                                      item.completed
                                          ? TextDecoration.lineThrough
                                          : TextDecoration.none,
                                  color:
                                      item.completed
                                          ? Colors.grey
                                          : Colors.black,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (item.dueDate != null)
                                    Text(
                                      '期限: ${DateFormat('yyyy/MM/dd').format(item.dueDate!)}',
                                      style: TextStyle(
                                        color:
                                            item.dueDate!.isBefore(
                                                      DateTime.now(),
                                                    ) &&
                                                    !item.completed
                                                ? Colors.red
                                                : Colors.grey,
                                      ),
                                    ),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6.0,
                                          vertical: 2.0,
                                        ),
                                        decoration: BoxDecoration(
                                          color: item.priority.color
                                              .withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(
                                            4.0,
                                          ),
                                        ),
                                        child: Text(
                                          '優先度: ${item.priority.label}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: item.priority.color,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8.0),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6.0,
                                          vertical: 2.0,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(
                                            4.0,
                                          ),
                                        ),
                                        child: Text(
                                          item.category,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.blue,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              onTap: () {
                                final originalIndex = _todoItems.indexOf(item);
                                _editTodoItem(originalIndex);
                              },
                              // 編集アイコン
                              trailing: IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () {
                                  final originalIndex = _todoItems.indexOf(
                                    item,
                                  );
                                  _editTodoItem(originalIndex);
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
      // 新しいTODOを追加するFAB
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _showAddTodoDialog(context);
        },
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  // ソートオプションを表示するダイアログ
  void _showSortOptions(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('並び替え'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSortOption(SortMethod.createdDate, '作成日'),
              _buildSortOption(SortMethod.dueDate, '期限日'),
              _buildSortOption(SortMethod.priority, '優先度'),
              _buildSortOption(SortMethod.category, 'カテゴリー'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
          ],
        );
      },
    );
  }

  // フィルターオプションを表示するダイアログ
  void _showFilterOptions(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('カテゴリーでフィルター'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final category in _categories)
                  ListTile(
                    title: Text(category),
                    onTap: () {
                      setState(() {
                        _filterCategory = category;
                      });
                      Navigator.pop(context);
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  _filterCategory = null;
                });
                Navigator.pop(context);
              },
              child: const Text('すべて表示'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
          ],
        );
      },
    );
  }

  // 詳細なTODO追加ダイアログを表示
  void _showAddTodoDialog(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => TodoEditScreen(
              todo: TodoItem(title: '', completed: false),
              categories: _categories,
              onSave: (newTodo) {
                setState(() {
                  _todoItems.add(newTodo);
                  _updateCategories();
                  _sortTodos();
                  _applyCompletedTasksVisibility();
                });
                _saveTodos();
                Navigator.pop(context);
              },
            ),
      ),
    );
  }

  // ソートオプションのUIを構築
  Widget _buildSortOption(SortMethod method, String label) {
    return RadioListTile<SortMethod>(
      title: Text(label),
      value: method,
      groupValue: _currentSortMethod,
      onChanged: (SortMethod? value) {
        setState(() {
          _currentSortMethod = value!;
          _sortTodos();
        });
        Navigator.pop(context);
      },
    );
  }

  // 設定ダイアログを表示する関数
  void _showSettingsDialog(BuildContext context) {
    // ダイアログで使用する一時的な値を設定
    int tempDeleteDays = _completedTasksDeleteDays;
    bool tempShowCompleted = _showCompletedTasks;

    // 通知設定用の一時変数（デフォルト値を設定）
    bool tempEnableDueReminders = false;
    int tempReminderTime = 24;
    bool tempNotifyHighPriority = false;

    // StatefulBuilderでラップする前に通知設定を読み込む
    _notificationService.loadNotificationSettings().then((settings) {
      tempEnableDueReminders = settings['enableDueReminders'];
      tempReminderTime = settings['reminderTime'];
      tempNotifyHighPriority = settings['notifyHighPriority'];

      // 設定が読み込まれた後でダイアログを表示
      showDialog(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: const Text('設定'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 完了タスクの表示設定
                      SwitchListTile(
                        title: const Text('完了タスクを表示'),
                        subtitle: const Text('完了済みのタスクをリストに表示するかどうか'),
                        value: tempShowCompleted,
                        onChanged: (value) {
                          setState(() {
                            tempShowCompleted = value;
                          });
                        },
                      ),
                      const Divider(),

                      // 完了タスクの自動削除設定
                      const Text(
                        '完了タスクを自動削除：',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),

                      RadioListTile<int>(
                        title: const Text('削除しない'),
                        value: 0,
                        groupValue: tempDeleteDays,
                        onChanged: (value) {
                          setState(() {
                            tempDeleteDays = value!;
                          });
                        },
                      ),
                      RadioListTile<int>(
                        title: const Text('7日後に削除'),
                        value: 7,
                        groupValue: tempDeleteDays,
                        onChanged: (value) {
                          setState(() {
                            tempDeleteDays = value!;
                          });
                        },
                      ),
                      RadioListTile<int>(
                        title: const Text('14日後に削除'),
                        value: 14,
                        groupValue: tempDeleteDays,
                        onChanged: (value) {
                          setState(() {
                            tempDeleteDays = value!;
                          });
                        },
                      ),
                      RadioListTile<int>(
                        title: const Text('30日後に削除'),
                        value: 30,
                        groupValue: tempDeleteDays,
                        onChanged: (value) {
                          setState(() {
                            tempDeleteDays = value!;
                          });
                        },
                      ),

                      const Divider(),

                      // 通知設定
                      const Text(
                        '通知設定：',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),

                      // FutureBuilderを使わずに直接設定を表示
                      SwitchListTile(
                        title: const Text('期限リマインダーを有効にする'),
                        subtitle: const Text('期限が近づいたタスクを通知します'),
                        value: tempEnableDueReminders,
                        onChanged: (value) {
                          setState(() {
                            tempEnableDueReminders = value;
                          });
                        },
                      ),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: DropdownButtonFormField<int>(
                          decoration: const InputDecoration(
                            labelText: '期限の何時間前に通知するか',
                          ),
                          value: tempReminderTime,
                          items: [
                            const DropdownMenuItem(
                              value: 1,
                              child: Text('1時間前'),
                            ),
                            const DropdownMenuItem(
                              value: 3,
                              child: Text('3時間前'),
                            ),
                            const DropdownMenuItem(
                              value: 6,
                              child: Text('6時間前'),
                            ),
                            const DropdownMenuItem(
                              value: 12,
                              child: Text('12時間前'),
                            ),
                            const DropdownMenuItem(
                              value: 24,
                              child: Text('24時間前'),
                            ),
                            const DropdownMenuItem(
                              value: 48,
                              child: Text('2日前'),
                            ),
                            const DropdownMenuItem(
                              value: 72,
                              child: Text('3日前'),
                            ),
                          ],
                          onChanged:
                              tempEnableDueReminders
                                  ? (value) {
                                    setState(() {
                                      tempReminderTime = value!;
                                    });
                                  }
                                  : null,
                        ),
                      ),

                      const SizedBox(height: 16),

                      SwitchListTile(
                        title: const Text('優先度の高いタスクの通知'),
                        subtitle: const Text('優先度が高いタスクが追加されたときに通知します'),
                        value: tempNotifyHighPriority,
                        onChanged: (value) {
                          setState(() {
                            tempNotifyHighPriority = value;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('キャンセル'),
                  ),
                  TextButton(
                    onPressed: () {
                      // 設定を保存して適用する
                      this.setState(() {
                        _completedTasksDeleteDays = tempDeleteDays;
                        _showCompletedTasks = tempShowCompleted;
                      });
                      _saveSettings();
                      _applyCompletedTasksVisibility();
                      _cleanupCompletedTasks();

                      // 通知設定を保存
                      _notificationService.saveNotificationSettings(
                        enableDueReminders: tempEnableDueReminders,
                        reminderTime: tempReminderTime,
                        notifyHighPriority: tempNotifyHighPriority,
                      );

                      // 通知を再スケジュール
                      _notificationService.rescheduleAllNotifications(
                        _todoItems,
                      );

                      Navigator.pop(context);
                    },
                    child: const Text('保存'),
                  ),
                ],
              );
            },
          );
        },
      );
    });
  }
}

class TodoItem {
  String title;
  bool completed;
  DateTime? dueDate;
  Priority priority;
  String category;
  String id;
  DateTime? completedDate; // 完了日時を追加

  TodoItem({
    required this.title,
    required this.completed,
    this.dueDate,
    this.priority = Priority.medium,
    this.category = 'その他',
    String? id,
    this.completedDate,
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch.toString();

  // JSON変換のためのメソッド
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'completed': completed,
      'dueDate': dueDate?.toIso8601String(),
      'priority': priority.index,
      'category': category,
      'completedDate': completedDate?.toIso8601String(), // 完了日時を保存
    };
  }

  // JSONからオブジェクトを作成するファクトリメソッド
  factory TodoItem.fromJson(Map<String, dynamic> json) {
    return TodoItem(
      id: json['id'],
      title: json['title'],
      completed: json['completed'],
      dueDate: json['dueDate'] != null ? DateTime.parse(json['dueDate']) : null,
      priority: Priority.values[json['priority'] ?? 1],
      category: json['category'] ?? 'その他',
      completedDate:
          json['completedDate'] != null
              ? DateTime.parse(json['completedDate'])
              : null, // 完了日時を読み込み
    );
  }
}

enum Priority { low, medium, high }

// 優先度に関連する拡張機能
extension PriorityExtension on Priority {
  String get label {
    switch (this) {
      case Priority.low:
        return '低';
      case Priority.medium:
        return '中';
      case Priority.high:
        return '高';
    }
  }

  Color get color {
    switch (this) {
      case Priority.low:
        return Colors.green;
      case Priority.medium:
        return Colors.orange;
      case Priority.high:
        return Colors.red;
    }
  }
}

// TODO編集画面
class TodoEditScreen extends StatefulWidget {
  final TodoItem todo;
  final Set<String> categories;
  final Function(TodoItem) onSave;

  const TodoEditScreen({
    super.key,
    required this.todo,
    required this.categories,
    required this.onSave,
  });

  @override
  State<TodoEditScreen> createState() => _TodoEditScreenState();
}

class _TodoEditScreenState extends State<TodoEditScreen> {
  late TextEditingController _titleController;
  late DateTime? _selectedDueDate;
  late Priority _selectedPriority;
  late String _selectedCategory;
  late bool _isCompleted;
  final TextEditingController _newCategoryController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.todo.title);
    _selectedDueDate = widget.todo.dueDate;
    _selectedPriority = widget.todo.priority;
    _selectedCategory = widget.todo.category;
    _isCompleted = widget.todo.completed;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _newCategoryController.dispose();
    super.dispose();
  }

  // 日付選択ダイアログを表示
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDueDate ?? DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime(2030),
      locale: const Locale('ja', 'JP'),
    );
    if (picked != null && picked != _selectedDueDate) {
      setState(() {
        _selectedDueDate = picked;
      });
    }
  }

  // 新しいカテゴリーを追加するダイアログを表示
  void _showAddCategoryDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('新しいカテゴリーを追加'),
          content: TextField(
            controller: _newCategoryController,
            decoration: const InputDecoration(hintText: 'カテゴリー名を入力してください'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () {
                if (_newCategoryController.text.isNotEmpty) {
                  setState(() {
                    _selectedCategory = _newCategoryController.text;
                  });
                  _newCategoryController.clear();
                  Navigator.pop(context);
                }
              },
              child: const Text('追加'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        title: Text(
          widget.todo.title.isEmpty ? '新しいTODO' : 'TODOを編集',
          style: const TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: () {
              // タイトルが空の場合は保存しない
              if (_titleController.text.isEmpty) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('タイトルを入力してください')));
                return;
              }

              final editedTodo = TodoItem(
                id: widget.todo.id,
                title: _titleController.text,
                completed: _isCompleted,
                dueDate: _selectedDueDate,
                priority: _selectedPriority,
                category: _selectedCategory,
                completedDate:
                    _isCompleted && !widget.todo.completed
                        ? DateTime.now()
                        : widget.todo.completedDate,
              );

              // 通知サービスのインスタンスを取得
              final notificationService = NotificationService();

              // 期限リマインダーの設定
              if (_selectedDueDate != null && !_isCompleted) {
                notificationService.scheduleDueReminder(editedTodo);
              } else {
                // 期限がない場合や完了した場合は通知をキャンセル
                notificationService.cancelNotification(editedTodo.id);
              }

              // 優先度の高いタスクが新規追加された場合に通知
              if (editedTodo.priority == Priority.high &&
                  widget.todo.title.isEmpty) {
                notificationService.notifyHighPriorityTask(editedTodo);
              }

              widget.onSave(editedTodo);
            },
            child: const Text('保存', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // タイトル入力
            const Text('タイトル', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8.0),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                hintText: 'TODOのタイトルを入力...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16.0),

            // 完了状態
            Row(
              children: [
                Checkbox(
                  value: _isCompleted,
                  onChanged: (value) {
                    setState(() {
                      _isCompleted = value ?? false;
                    });
                  },
                ),
                const Text('完了'),
              ],
            ),
            const SizedBox(height: 16.0),

            // 期限日の設定
            const Text('期限日', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8.0),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedDueDate == null
                        ? '期限日なし'
                        : '期限日: ${DateFormat('yyyy/MM/dd').format(_selectedDueDate!)}',
                  ),
                ),
                TextButton(
                  onPressed: () => _selectDate(context),
                  child: const Text('日付を選択'),
                ),
                if (_selectedDueDate != null)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      setState(() {
                        _selectedDueDate = null;
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16.0),

            // 優先度の設定
            const Text('優先度', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8.0),
            SegmentedButton<Priority>(
              segments: [
                ButtonSegment<Priority>(
                  value: Priority.low,
                  label: Text(Priority.low.label),
                  icon: Icon(Icons.arrow_downward, color: Priority.low.color),
                ),
                ButtonSegment<Priority>(
                  value: Priority.medium,
                  label: Text(Priority.medium.label),
                  icon: Icon(Icons.remove, color: Priority.medium.color),
                ),
                ButtonSegment<Priority>(
                  value: Priority.high,
                  label: Text(Priority.high.label),
                  icon: Icon(Icons.arrow_upward, color: Priority.high.color),
                ),
              ],
              selected: {_selectedPriority},
              onSelectionChanged: (Set<Priority> selected) {
                setState(() {
                  _selectedPriority = selected.first;
                });
              },
            ),
            const SizedBox(height: 16.0),

            // カテゴリーの設定
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'カテゴリー',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('新規カテゴリー'),
                  onPressed: () => _showAddCategoryDialog(context),
                ),
              ],
            ),
            const SizedBox(height: 8.0),
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: [
                ...widget.categories.map((category) {
                  return DropdownMenuItem<String>(
                    value: category,
                    child: Text(category),
                  );
                }),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedCategory = value;
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

enum SortMethod { createdDate, dueDate, priority, category }

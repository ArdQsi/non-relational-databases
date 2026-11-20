#!/bin/bash
# Пункт 1. Создание пользователей для работы с учебными базами.
# Пользователь создаётся в той базе, с которой работает (она же база аутентификации).
# Пароль всех пользователей: Pass_123
A="mongodb://admin:Admin_123@127.0.0.1:27017/?authSource=admin"

mongosh --quiet "$A" --eval '
  // [база, пользователь, встроенные роли]
  const users = [
    ["school",  "teacher",   [{role:"readWrite", db:"school"}]],    // чтение и запись всей базы
    ["school",  "ann",       []],                                   // без ролей, роли выдадим в пункте 3
    ["shop",    "manager",   [{role:"readWrite", db:"shop"}]],
    ["library", "librarian", [{role:"read",      db:"library"}]]    // только чтение
  ];
  for (const [d, u, roles] of users) {
    const x = db.getSiblingDB(d);
    try { x.dropUser(u) } catch (e) {}
    x.createUser({user: u, pwd: "Pass_123", roles: roles});
    print("создан пользователь " + u + " в базе " + d);
  }
  print("Пользователи");
  for (const d of ["school", "shop", "library"])
    db.getSiblingDB(d).getUsers().users.forEach(u =>
      print(d + ": " + u.user + " -> " + (u.roles.map(r => r.role + "@" + r.db).join(", ") || "(нет ролей)")));'
echo "Готово"

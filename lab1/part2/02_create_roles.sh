#!/bin/bash
# Пункт 2. Создание собственных ролей с разными наборами операций (база school).
A="mongodb://admin:Admin_123@127.0.0.1:27017/?authSource=admin"

mongosh --quiet "$A" --eval '
  const d = db.getSiblingDB("school");
  for (const r of ["reader", "grader"]) { try { d.dropRole(r) } catch (e) {} }

  // reader: только чтение всех коллекций базы (collection: "" = вся база)
  d.createRole({role: "reader", roles: [],
    privileges: [{resource: {db: "school", collection: ""}, actions: ["find", "listCollections"]}]});

  // grader: чтение, добавление и изменение, но только в коллекции grades
  d.createRole({role: "grader", roles: [],
    privileges: [{resource: {db: "school", collection: "grades"}, actions: ["find", "insert", "update"]}]});

  print("Роли базы school");
  d.getRoles({showPrivileges: true}).roles.forEach(r =>
    print(r.role + ": " + r.privileges.map(p => p.resource.db + "." + (p.resource.collection || "*") + " [" + p.actions.join(",") + "]").join("; ")));'
echo "Готово"

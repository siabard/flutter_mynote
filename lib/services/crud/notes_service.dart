import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mynote/services/crud/crud_exceptions.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

const createNoteTable = '''

CREATE TABLE IF NOT EXISTS note (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
	user_id INTEGER NOT NULL,
	"text" TEXT NOT NULL,
	is_synced_with_cloud INTEGER DEFAULT 0 NOT NULL,
	CONSTRAINT note_FK FOREIGN KEY (user_id) REFERENCES "user"(id) ON DELETE CASCADE
);
      ''';
const createUserTable = '''

CREATE TABLE IF NOT EXISTS "user" (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
	email TEXT NOT NULL,
	CONSTRAINT user_UN UNIQUE (email)
);

      ''';
const dbName = "notes";
const emailColumn = 'email';
const idColumn = 'id';
const isSyncedWithCloudColumn = 'is_synced_with_cloud';
const noteTable = 'note';
const textColumn = 'text';

const userIdColumn = 'user_id';

const userTable = 'user';

@immutable
class DatabaseNote {
  final int id;
  final int userId;
  final String text;
  final bool isSyncedWithCloud;

  const DatabaseNote({
    required this.id,
    required this.userId,
    required this.text,
    required this.isSyncedWithCloud,
  });

  DatabaseNote.fromRow(Map<String, Object?> map)
      : id = map[idColumn] as int,
        userId = map[userIdColumn] as int,
        text = map[textColumn] as String,
        isSyncedWithCloud =
            (map[isSyncedWithCloudColumn] as int == 1 ? true : false);

  @override
  int get hashCode => id.hashCode;

  @override
  bool operator ==(covariant DatabaseNote other) => id == other.id;

  @override
  String toString() =>
      'Note, ID = $id, userId = $userId, isSyncedWithCloud = $isSyncedWithCloud';
}

@immutable
class DatabaseUser {
  final int id;
  final String email;

  const DatabaseUser({
    required this.id,
    required this.email,
  });

  DatabaseUser.fromRow(Map<String, Object?> map)
      : id = map[idColumn] as int,
        email = map[emailColumn] as String;

  @override
  int get hashCode => id.hashCode;

  @override
  bool operator ==(covariant DatabaseUser other) => id == other.id;

  @override
  String toString() => 'Person, ID = $id, email = $email';
}

class NotesService {
  Database? _db;
  List<DatabaseNote> _notes = [];
  final _notesStreamController =
      StreamController<List<DatabaseNote>>.broadcast();
  Stream<List<DatabaseNote>> get allNotes => _notesStreamController.stream;
  static final NotesService _shared = NotesService._sharedInstance();

  NotesService._sharedInstance();
  factory NotesService() => _shared;



  Future<void> _ensureDbIsOpen() async {
    try {
      await open();
    } on DatabaseAlreadyOpenException {
      // empty
    }
  }

  Future<void> close() async {
    final db = _db;

    if (db == null) {
      throw DatabaseIsNotOpen();
    } else {
      await db.close();
      _db = null;
    }
  }

  Future<DatabaseNote> createNote({
    required DatabaseUser owner,
  }) async {
    await _ensureDbIsOpen();
    final db = _getDatabaseOrThrow();

    // make sure owner exists in the database
    final dbUser = await getUser(email: owner.email);
    if (dbUser != owner) {
      throw CouldNotFindUser();
    }

    const text = '';
    // create note
    final noteId = await db.insert(noteTable, {
      userIdColumn: owner.id,
      textColumn: text,
      isSyncedWithCloudColumn: 1,
    });

    final note = DatabaseNote(
      id: noteId,
      userId: owner.id,
      text: text,
      isSyncedWithCloud: true,
    );

    _notes.add(note);
    _notesStreamController.add(_notes);

    return note;
  }

  Future<DatabaseUser> createUser({required String email}) async {
    await _ensureDbIsOpen();
    final db = _getDatabaseOrThrow();

    final results = await db.query(
      userTable,
      limit: 1,
      where: 'email = ?',
      whereArgs: [email.toLowerCase()],
    );

    if (results.isNotEmpty) {
      throw UserAlreadyExists();
    }

    final userId = await db.insert(userTable, {
      emailColumn: email.toLowerCase(),
    });

    return DatabaseUser(id: userId, email: email);
  }

  Future<int> deleteAllNotes() async {
    await _ensureDbIsOpen();

    final db = _getDatabaseOrThrow();
    final numberOfDeletions = await db.delete(noteTable);

    _notes = [];
    _notesStreamController.add(_notes);

    return numberOfDeletions;
  }

  Future<void> deleteNote({required int id}) async {
    await _ensureDbIsOpen();

    final db = _getDatabaseOrThrow();
    final deletedCount = await db.delete(
      noteTable,
      where: 'id = ? ',
      whereArgs: [id],
    );

    if (deletedCount == 0) {
      throw CouldNotDeleteNote();
    } else {
      _notes.removeWhere((note) => note.id == id);
      _notesStreamController.add(_notes);
    }
  }

  Future<void> deleteUser({required String email}) async {
    await _ensureDbIsOpen();
    final db = _getDatabaseOrThrow();

    final deletedCount = await db.delete(
      userTable,
      where: 'email = ?',
      whereArgs: [email.toLowerCase()],
    );

    if (deletedCount != 1) {
      throw CouldNotDeleteUser();
    }
  }

  Future<Iterable<DatabaseNote>> getAllNotes() async {
    await _ensureDbIsOpen();
    final db = _getDatabaseOrThrow();

    final notes = await db.query(noteTable);

    return notes.map((n) => DatabaseNote.fromRow(n));
  }

  Future<DatabaseNote> getNote({required int id}) async {
    await _ensureDbIsOpen();
    final db = _getDatabaseOrThrow();
    final notes = await db.query(
      noteTable,
      limit: 1,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (notes.isEmpty) {
      throw CouldNotFindNote();
    } else {
      final note = DatabaseNote.fromRow(notes.first);

      _notes.removeWhere((note) => note.id == id);
      _notes.add(note);
      _notesStreamController.add(_notes);

      return note;
    }
  }

  Future<DatabaseUser> getOrCreateUser({required String email}) async {
    try {
      final user = await getUser(email: email);
      return user;
    } on CouldNotFindUser {
      final createdUser = await createUser(email: email);
      return createdUser;
    } catch (e) {
      rethrow;
    }
  }

  Future<DatabaseUser> getUser({required String email}) async {
    await _ensureDbIsOpen();
    final db = _getDatabaseOrThrow();

    final results = await db.query(
      userTable,
      limit: 1,
      where: 'email = ?',
      whereArgs: [email.toLowerCase()],
    );

    if (results.isEmpty) {
      throw CouldNotFindUser();
    }

    return DatabaseUser.fromRow(results.first);
  }

  Future<void> open() async {
    if (_db != null) {
      throw DatabaseAlreadyOpenException();
    }

    try {
      final docPath = await getApplicationDocumentsDirectory();
      final dbPath = join(docPath.path, "db", dbName);
      final db = await openDatabase(dbPath);

      _db = db;

      await db.execute(createUserTable);

      await db.execute(createNoteTable);

      await _cacheNotes();
    } on MissingPlatformDirectoryException {
      throw UnableToGetDocumentsDirectory();
    }
  }

  Future<DatabaseNote> updateNote({
    required int id,
    required String text,
  }) async {
    await _ensureDbIsOpen();
    final db = _getDatabaseOrThrow();

    final updateCount = await db.update(
      noteTable,
      {
        textColumn: text,
        isSyncedWithCloudColumn: 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    if (updateCount == 0) {
      throw CouldNotUpdateNote();
    } else {
      return await getNote(id: id);
    }
  }

  Future<void> _cacheNotes() async {
    final allNotes = await getAllNotes();
    _notes = allNotes.toList();
    _notesStreamController.add(_notes);
  }

  Database _getDatabaseOrThrow() {
    final db = _db;

    if (db == null) {
      throw DatabaseIsNotOpen();
    } else {
      return db;
    }
  }
}

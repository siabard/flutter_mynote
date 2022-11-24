import 'package:flutter/material.dart';
import 'package:mynote/services/auth/auth_service.dart';
import 'package:mynote/view/notes/create_update_note_view.dart';

import 'constants/routes.dart';
import 'view/login_view.dart';
import 'view/notes/notes_view.dart';
import 'view/register_view.dart';
import 'view/verify_email_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const HomePage(),
      routes: {
        loginRoute: (context) => const LoginView(),
        registRoute: (context) => const RegisterView(),
        notesRoute: (context) => const NotesView(),
        verifyEmailRoute: (context) => const VerifyEmailView(),
        createUpdateNoteRoute: (context) => const CreateUpdateNoteView(),
      }));
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: AuthService.firebase().initialize(),
        builder: (context, snapshot) {
          switch (snapshot.connectionState) {
            case ConnectionState.done:
              final user = AuthService.firebase().currentUser;

              if (user == null) {
                return const LoginView();
              }

              final emailVerified = user.isEmailVerified;
              if (emailVerified == true) {
                return const NotesView();
              } else {
                return const VerifyEmailView();
              }

            default:
              return const CircularProgressIndicator();
          }
        });
  }
}

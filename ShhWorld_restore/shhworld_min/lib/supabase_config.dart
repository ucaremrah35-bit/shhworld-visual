import 'package:supabase_flutter/supabase_flutter.dart';

// Projene ait URL (senin projenden daha önce paylaştığın URL):
const supabaseUrl = 'https://zckuqzauwltcugnqkmta.supabase.co';

// Bize verdiğin anon key (public):
const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inpja3VxemF1d2x0Y3VnbnFrbXRhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQwNjQ0MDQsImV4cCI6MjA3OTY0MDQwNH0.FUa7Kdj3bTbdKTAgKnWjDRynerM7q55xS1Gk_nmXDB8';

Future<void> initSupabase() async {
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
}

final supa = Supabase.instance.client;

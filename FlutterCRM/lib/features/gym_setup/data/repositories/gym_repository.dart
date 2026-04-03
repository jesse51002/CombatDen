import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crm/core/errors/exceptions.dart';

/// Repository for gym setup data access
class GymRepository {
  final SupabaseClient _supabase;

  GymRepository({SupabaseClient? supabaseClient})
      : _supabase =
            supabaseClient ?? Supabase.instance.client;

  /// Returns the owner employee record for [userId],
  /// or null if the user doesn't own any gym.
  Future<Map<String, dynamic>?> getOwnerEmployee(
    String userId,
  ) async {
    try {
      final response = await _supabase
          .from('gym_employees')
          .select('*, gyms(*)')
          .eq('user_id', userId)
          .eq('employee_type', 'owner')
          .maybeSingle();
      return response;
    } on PostgrestException catch (e) {
      throw DatabaseException(e.message);
    }
  }

  /// Returns the gym by [gymId], or null.
  Future<Map<String, dynamic>?> getGymById(
    String gymId,
  ) async {
    try {
      final response = await _supabase
          .from('gyms')
          .select()
          .eq('gym_id', gymId)
          .maybeSingle();
      return response;
    } on PostgrestException catch (e) {
      throw DatabaseException(e.message);
    }
  }

  /// Creates a gym and its owner employee in one flow.
  /// Returns the created gym row.
  Future<Map<String, dynamic>> setupGym({
    required String gymName,
    required String userId,
    required String firstName,
    required String lastName,
  }) async {
    try {
      final gym = await _supabase
          .from('gyms')
          .insert({
            'gym_name': gymName,
          })
          .select()
          .single();

      final gymId = gym['gym_id'] as String;

      await _supabase.from('gym_employees').insert({
        'user_id': userId,
        'gym_id': gymId,
        'employee_type': 'owner',
        'first_name': firstName,
        'last_name': lastName,
      });

      return gym;
    } on PostgrestException catch (e) {
      throw DatabaseException(e.message);
    }
  }
}

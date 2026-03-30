import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crm/core/errors/exceptions.dart';

/// Repository for gym and user gym profile data access
class GymRepository {
  final SupabaseClient _supabase;

  GymRepository({SupabaseClient? supabaseClient})
      : _supabase =
            supabaseClient ?? Supabase.instance.client;

  /// Returns the gym owned by [userId], or null
  Future<Map<String, dynamic>?> getGymByOwnerId(
    String userId,
  ) async {
    try {
      final response = await _supabase
          .from('gyms')
          .select()
          .eq('owner_id', userId)
          .maybeSingle();
      return response;
    } on PostgrestException catch (e) {
      throw DatabaseException(e.message);
    }
  }

  /// Returns the user gym profile, or null
  Future<Map<String, dynamic>?> getUserGymProfile({
    required String userId,
    required String gymId,
  }) async {
    try {
      final response = await _supabase
          .from('user_gym_profiles')
          .select()
          .eq('user_id', userId)
          .eq('gym_id', gymId)
          .maybeSingle();
      return response;
    } on PostgrestException catch (e) {
      throw DatabaseException(e.message);
    }
  }

  /// Creates a gym and returns the created row
  Future<Map<String, dynamic>> createGym({
    required String gymName,
    required String ownerId,
  }) async {
    try {
      final response = await _supabase
          .from('gyms')
          .insert({
            'gym_name': gymName,
            'owner_id': ownerId,
          })
          .select()
          .single();
      return response;
    } on PostgrestException catch (e) {
      throw DatabaseException(e.message);
    }
  }

  /// Updates rank configuration for a gym
  Future<void> updateGymRankConfig({
    required String gymId,
    required bool rankEnabled,
    String? rankPreset,
  }) async {
    try {
      await _supabase.from('gyms').update({
        'rank_enabled': rankEnabled,
        'rank_preset': rankPreset,
      }).eq('gym_id', gymId);
    } on PostgrestException catch (e) {
      throw DatabaseException(e.message);
    }
  }

  /// Creates a user gym profile
  Future<void> createUserGymProfile({
    required String userId,
    required String gymId,
    required String firstName,
    required String lastName,
  }) async {
    try {
      await _supabase.from('user_gym_profiles').insert({
        'user_id': userId,
        'gym_id': gymId,
        'first_name': firstName,
        'last_name': lastName,
      });
    } on PostgrestException catch (e) {
      throw DatabaseException(e.message);
    }
  }
}

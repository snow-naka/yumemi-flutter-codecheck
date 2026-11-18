import '../../models/api_failure.dart';
import '../../models/repository_models.dart';

sealed class SearchState {
  const SearchState();
  String? get query;
}

final class SearchInitial extends SearchState {
  const SearchInitial();
  @override
  String? get query => null;
}

final class SearchLoading extends SearchState {
  const SearchLoading(this.query);
  @override
  final String query;
}

final class SearchSuccess extends SearchState {
  const SearchSuccess(this.query, this.result);
  @override
  final String query;
  final SearchPage result;
}

final class SearchFailure extends SearchState {
  const SearchFailure(this.query, this.failure);
  @override
  final String query;
  final ApiFailure failure;
}

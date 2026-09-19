import 'package:flutter/foundation.dart';

class HomeNavigationRequest {
  const HomeNavigationRequest({this.explore = false, this.query = ''});

  final bool explore;
  final String query;
}

/// Entrega a la Home existente una búsqueda o navegación desde el detalle.
/// No recrea rutas ni altera el estado del reproductor.
class HomeNavigationController extends ValueNotifier<HomeNavigationRequest?> {
  HomeNavigationController() : super(null);

  void open({bool explore = false, String query = ''}) {
    value = HomeNavigationRequest(explore: explore, query: query);
  }
}

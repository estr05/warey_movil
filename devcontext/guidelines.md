# 📱 Mobile App Development Guidelines (Vibe Coding)

## 1. Stack Tecnológico Principal
Las aplicaciones móviles deben ser construidas utilizando el siguiente enfoque:
1. **Core:** Flutter (Dart).
2. **Arquitectura UI:** Separación estricta entre la lógica de negocio y la interfaz de usuario.
3. **Estilos y Temas:** Uso del sistema de temas nativo de Flutter (`ThemeData`) para garantizar consistencia global (Modo Claro / Modo Oscuro) en lugar de estilos quemados (hardcoded) en cada widget.
4. **Llamadas a API:** Uso de clientes HTTP robustos como `Dio` con interceptores bien configurados.

---

## 2. Estética de Diseño (UI/UX)
El aspecto visual es CRÍTICO. Si la aplicación luce básica, simple o genérica, se considera un fallo. Debes exigir siempre a la IA lo siguiente:

1. **Estética Premium ("Wow Factor"):** 
   El usuario debe quedar impresionado a primera vista. Utiliza las mejores prácticas de diseño móvil moderno (colores vibrantes, glassmorphism, sombras suaves y elevaciones elegantes) para crear una primera impresión impactante.
2. **Excelencia Visual Prioritaria:**
   - **Evita colores genéricos:** (rojo plano, azul brillante de sistema). Usa paletas seleccionadas y armoniosas (ej. colores basados en HSL, modos oscuros pulidos).
   - **Tipografía Moderna:** Exige el uso de Google Fonts modernas (ej. `Inter`, `Roboto`, `Outfit`, `Poppins`) en lugar de las fuentes del sistema por defecto. Define un `TextTheme` global.
   - **Gradientes:** Usa gradientes suaves y modernos en lugar de colores sólidos para botones de acción principal (CTAs) o fondos de tarjetas.
3. **Diseño Dinámico e Interactivo:** 
   Una interfaz que se siente viva fomenta la interacción. 
   - Añade micro-animaciones en las transiciones entre pantallas (`PageRouteBuilder`, `Hero` animations).
   - Usa efectos visuales al tocar elementos (ripples mejorados, escalas de botones en el `onTapDown`).
   - Muestra "Skeleton Loaders" (Shimmer effects) en lugar de un simple `CircularProgressIndicator` al cargar datos.
4. **Cero Placeholders Visuales (Sin pantallas "vacías"):** 
   Si se requiere una imagen o un icono, no dejes recuadros grises vacíos. Exige a la IA que use paquetes como `cached_network_image` con URLs de demostración de alta calidad (ej. Unsplash) o iconos ilustrativos relevantes.

---

## 3. Paleta de Colores Premium (DevUbi / Warey)
Para garantizar la consistencia estética y el "Wow Factor", el proyecto se rige estrictamente por la siguiente paleta de colores. Esta paleta combina elegancia con buen contraste y se adapta tanto a modo claro como oscuro:

| # | Nombre descriptivo | Hex | RGB | Uso recomendado |
|---|--------------------|------|------|----------------|
| 1 | **Azul Profundo** | `#0A3D62` | 10, 61, 98 | Encabezados, barra de navegación, botones primarios |
| 2 | **Cian Vibrante** | `#00A8CC` | 0, 168, 204 | Acciones secundarias, enlaces, resaltado de estado activo |
| 3 | **Gris Oscuro** | `#2C3E50` | 44, 62, 80 | Texto principal, iconos, fondos de tarjetas |
| 4 | **Verde Acuático** | `#27AE60` | 39, 174, 96 | Mensajes de éxito, badges, indicadores “online” |
| 5 | **Naranja Coral** | `#E67E22` | 230, 126, 34 | Mensajes de alerta/advertencia, botones de “call‑to‑action” |
| 6 | **Blanco Humo** | `#F4F6F9` | 244, 246, 249 | Fondos de pantalla, áreas de contenido amplio, formularios |
| 7 | **Gris Claro** | `#ECF0F1` | 236, 240, 241 | Bordes, divisores, fondos de tarjetas secundarias |

> **Tip de implementación:**  
> En Flutter, define la paleta en `ThemeData` usando `ColorScheme` o variables constantes de la siguiente manera:

```dart
class AppColors {
  static const Color deepBlue      = Color(0xFF0A3D62);
  static const Color vibrantCyan   = Color(0xFF00A8CC);
  static const Color darkGray      = Color(0xFF2C3E50);
  static const Color aquaGreen     = Color(0xFF27AE60);
  static const Color coralOrange   = Color(0xFFE67E22);
  static const Color smokeWhite    = Color(0xFFF4F6F9);
  static const Color lightGray     = Color(0xFFECF0F1);
}
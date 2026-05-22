---

## 5. Directrices para el Desarrollo con Vibe Coding (AI-Assisted)
Para maximizar la eficiencia y coherencia al construir el sistema utilizando agentes de Inteligencia Artificial (Vibe Coding), se establecen las siguientes directrices:

### 5.1. Contexto Explícito y Atómico
*   **Archivos Pequeños y Focales:** Mantener los widgets de Flutter y los controladores de Laravel pequeños y enfocados en una sola responsabilidad. Esto facilita que el agente IA comprenda el contexto completo sin perder información.
*   **Comentarios de Intención:** Escribir comentarios claros explicando *por qué* se hace algo (reglas de negocio), no solo *qué* hace el código. Esto guía a la IA para generar soluciones alineadas con la visión del proyecto.
*   **Instrucciones Precisas (Prompting):** Al solicitar cambios, especificar claramente la ruta del archivo, la línea o componente objetivo, y proporcionar ejemplos de cómo debe lucir o comportarse el resultado final.

### 5.2. Estética y Diseño Premium (Vibe UI/UX)
*   **Efecto "Wow" y Diseño Moderno:** Las interfaces generadas para Flutter y las vistas web deben ser premium y modernas. Se deben evitar colores genéricos y diseños básicos.
*   **Paletas y Tipografía:** Utilizar paletas de colores armoniosas, modos oscuros elegantes (dark mode nativo), efectos de glassmorfismo y tipografías modernas (ej. Inter, Roboto, Outfit) en lugar de las opciones por defecto.
*   **Micro-animaciones:** Implementar interacciones dinámicas. Se debe solicitar a la IA la inclusión de micro-animaciones (ej. paquetes de Lottie o animaciones implícitas en Flutter) para botones, transiciones, y estados de carga, dando un "vibe" responsivo y vivo.
*   **Cero Placeholders:** Exigir siempre la generación de datos de demostración estructurados o el uso de imágenes/assets reales (generados por herramientas si es necesario) para evaluar el diseño en condiciones reales.

### 5.3. Arquitectura y Patrones 
*   **Gestión de Estado (Flutter):** Declarar explícitamente el manejador de estado (Provider, Riverpod, Bloc, etc.) en los prompts para que la IA no mezcle patrones de arquitectura en la UI.
*   **Respuestas API (Laravel):** Indicar a la IA que todos los endpoints deben devolver respuestas JSON estandarizadas (ej. envoltorio con `success`, `data`, `message`) para un parseo predecible en el cliente móvil.
*   **Manejo de Errores Resiliente:** En el consumo de la API desde Flutter, instruir al agente para que siempre use bloques `try-catch`, implemente interceptores (ej. con Dio) y maneje tokens expirados o errores 500 con retroalimentación visual al usuario.

### 5.4. Flujo de Trabajo Iterativo
*   **Desarrollo Incremental:** Solicitar a la IA primero la estructura base (layout o scaffolding), verificar, y luego pedir iteraciones sobre la lógica, estilos y animaciones.
*   **Validación de Dependencias:** Al solicitar nuevas funcionalidades que requieran paquetes (`pubspec.yaml` o `composer.json`), pedir a la IA que verifique versiones compatibles y documente el comando exacto de instalación.

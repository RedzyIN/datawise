import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/theme_provider.dart';
import '../../models/theme_palette.dart';

class ColorPalettePage extends StatefulWidget {
  const ColorPalettePage({super.key});

  @override
  State<ColorPalettePage> createState() => _ColorPalettePageState();
}

class _ColorPalettePageState extends State<ColorPalettePage> {
  String? selectedKey;

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        final currentKey = selectedKey ?? themeProvider.palette.key;

        final selectedPalette = ThemePalette.fromKey(currentKey);

        return Scaffold(
          appBar: AppBar(title: const Text('Palet Warna')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Warna Aplikasi',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'DATAWISE memakai teal sebagai warna identitas. '
                'Setiap palet memiliki tampilan terang dan gelap; '
                'lihat preview sebelum menerapkannya.',
              ),
              const SizedBox(height: 20),

              // Daftar pilihan palet.
              ...ThemePalette.available.map((palette) {
                final isSelected = currentKey == palette.key;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _colorCircle(palette.light.primary),
                        const SizedBox(width: 5),
                        _colorCircle(palette.light.secondary),
                        const SizedBox(width: 5),
                        _colorCircle(palette.light.accent),
                      ],
                    ),
                    title: Text(
                      palette.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      isSelected ? 'Dipilih' : palette.description,
                    ),
                    trailing: Icon(
                      isSelected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    onTap: () {
                      setState(() {
                        selectedKey = palette.key;
                      });
                    },
                  ),
                );
              }),

              const SizedBox(height: 16),

              const Text(
                'Preview Tampilan',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              // Preview Light dan Dark.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildPreview(selectedPalette, isDark: false),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: _buildPreview(selectedPalette, isDark: true)),
                ],
              ),

              const SizedBox(height: 24),

              // Terapkan pilihan palet.
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await themeProvider.setPalette(currentKey);

                    if (!context.mounted) return;

                    Navigator.pop(context);

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Palet ${selectedPalette.name} berhasil diterapkan',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('Terapkan Palet'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _colorCircle(Color color) {
    return CircleAvatar(radius: 13, backgroundColor: color);
  }

  Widget _buildPreview(ThemePalette palette, {required bool isDark}) {
    final colors = isDark ? palette.dark : palette.light;

    return Theme(
      data: buildPaletteAppTheme(palette, isDark: isDark),
      child: Builder(
        builder: (context) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.primary),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isDark ? 'Dark Mode' : 'Light Mode',
                  style: TextStyle(
                    color: colors.text,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DATAWISE',
                        style: TextStyle(
                          color: colors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Contoh tampilan aplikasi',
                        style: TextStyle(color: colors.text, fontSize: 11),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: colors.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Tombol',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isDark ? colors.background : Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        height: 7,
                        decoration: BoxDecoration(
                          color: colors.accent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

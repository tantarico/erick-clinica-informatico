package com.clinicainformatica.api;

import java.nio.charset.StandardCharsets;
import java.util.*;

final class PdfDocument {
    private final StringBuilder stream = new StringBuilder();

    void text(float x, float y, float size, String text) {
        stream.append("BT\n/F1 ").append(format(size)).append(" Tf\n")
            .append(format(x)).append(" ").append(format(y)).append(" Td\n")
            .append("(").append(escape(text)).append(") Tj\nET\n");
    }

    void text(float x, float y, float size, String text, float red, float green, float blue) {
        stream.append("q\n")
            .append(formatColor(red)).append(" ").append(formatColor(green)).append(" ")
            .append(formatColor(blue)).append(" rg\n")
            .append("BT\n/F1 ").append(format(size)).append(" Tf\n")
            .append(format(x)).append(" ").append(format(y)).append(" Td\n")
            .append("(").append(escape(text)).append(") Tj\nET\nQ\n");
    }

    void fillRectangle(float x, float y, float width, float height,
        float red, float green, float blue) {
        stream.append("q\n")
            .append(formatColor(red)).append(" ").append(formatColor(green)).append(" ")
            .append(formatColor(blue)).append(" rg\n")
            .append(format(x)).append(" ").append(format(y)).append(" ")
            .append(format(width)).append(" ").append(format(height))
            .append(" re\nf\nQ\n");
    }

    void line(float x1, float y1, float x2, float y2, float width) {
        stream.append(format(x1)).append(" ").append(format(y1)).append(" m\n")
            .append(format(x2)).append(" ").append(format(y2)).append(" l\n")
            .append(format(width)).append(" w\nS\n");
    }

    void rectangle(float x, float y, float width, float height) {
        stream.append(format(x)).append(" ").append(format(y)).append(" ")
            .append(format(width)).append(" ").append(format(height))
            .append(" re\nS\n");
    }

    byte[] build() {
        String content = stream.toString();
        List<String> objects = List.of(
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
                + "/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica "
                + "/Encoding /WinAnsiEncoding >>",
            "<< /Length " + content.getBytes(StandardCharsets.ISO_8859_1).length
                + " >>\nstream\n" + content + "endstream"
        );

        byte[] header = "%PDF-1.4\n".getBytes(StandardCharsets.ISO_8859_1);
        StringBuilder body = new StringBuilder("%PDF-1.4\n");
        List<Integer> offsets = new ArrayList<>();
        for (int i = 0; i < objects.size(); i++) {
            offsets.add(body.toString().getBytes(StandardCharsets.ISO_8859_1).length);
            body.append(i + 1).append(" 0 obj\n")
                .append(objects.get(i)).append("\nendobj\n");
        }
        int xrefOffset = body.toString().getBytes(StandardCharsets.ISO_8859_1).length;
        body.append("xref\n0 6\n0000000000 65535 f \n");
        for (Integer offset : offsets) {
            body.append(String.format(Locale.ROOT, "%010d 00000 n \n", offset));
        }
        body.append("trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n")
            .append(xrefOffset).append("\n%%EOF");
        return body.toString().getBytes(StandardCharsets.ISO_8859_1);
    }

    private static String escape(String value) {
        return Objects.toString(value, "")
            .replace("\\", "\\\\")
            .replace("(", "\\(")
            .replace(")", "\\)")
            .replace("\r", "")
            .replace("\n", " ");
    }

    private static String format(float value) {
        return String.format(Locale.ROOT, "%.1f", value);
    }

    private static String formatColor(float value) {
        return String.format(Locale.ROOT, "%.3f", value);
    }
}

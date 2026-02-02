from pypdf import PdfReader

try:
    reader = PdfReader("SRS.pdf")
    text = ""
    for page in reader.pages:
        text += page.extract_text() + "\n"
    with open("srs_full.txt", "w", encoding="utf-8") as f:
        f.write(text)
    print("Successfully wrote srs_full.txt")
except Exception as e:
    print(f"Error reading PDF: {e}")

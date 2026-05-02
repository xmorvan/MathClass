# MathClass App

MathClass is an educational application designed for teachers and students to manage math exercises, assignments, and solutions.

## QR Code Login System

The app includes a QR code-based login system for students with persistent sessions. Here's how to use it:

### For Teachers:

1. **Generate QR Codes**:
   - Go to the Classes section in the teacher interface
   - Select a class from the list
   - Click the "Générer QR Codes" button
   - Save the PDF file containing QR codes for all students in the class

2. **Manage Student Sessions**:
   - Go to the "QR Codes" section in the sidebar
   - View all active student sessions
   - Approve or deny logout requests from students
   - Regenerate individual QR codes if needed

3. **Export QR Codes**:
   - Use the "Export PDF" button in the QR Codes management view
   - Print and distribute the QR codes to students

### For Students:

1. **Login with QR Code** (iOS only):
   - Launch the app and choose "Student" role
   - Position your QR code in front of the camera
   - Once scanned, you'll be automatically logged in

2. **Manual Login** (iOS and macOS):
   - Enter your first and last name in the login form
   - This method is available as backup or on platforms without camera access

3. **Persistent Sessions**:
   - Once logged in, your session remains active until you request logout
   - To logout, use the "Request Logout" button in the student interface
   - Your teacher will need to approve the logout request

## Security Features

- QR codes contain encrypted student credentials
- Each QR code has a 1-year validity period
- Session data is securely stored in the device keychain
- Each device gets a unique identifier to prevent unauthorized logins
- Teachers can revoke access by approving logout requests or regenerating QR codes

## Implementation Details

The QR code system is implemented with:
- CoreImage for QR code generation
- AVFoundation for QR scanning on iOS
- Keychain for secure credential storage
- Firebase for synchronizing session state between devices
- PDF generation for distributing QR codes

## Requirements

- iOS 16.0+ or macOS 12.0+
- Camera access for QR scanning (iOS only)
- Firebase account for backend services
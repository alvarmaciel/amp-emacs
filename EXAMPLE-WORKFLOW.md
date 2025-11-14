# Example Workflow: Debugging and Fixing a Python API

This document walks through a real-world example of using amp-emacs to debug and fix a bug in a Python Flask API.

## Scenario

You're working on a Flask API that handles user authentication. There's a bug report that users can't log in, but the error messages are unclear. Let's use Amp to help debug and fix it.

## Setup

**Project structure:**
```
my-api/
├── app.py
├── auth.py
├── models.py
└── tests/
    └── test_auth.py
```

## Step 1: Start Your Amp Session

In Emacs:
```
M-x amp-start
```

You see: `Amp server started on port 9000. Run 'amp --ide' in your project.`

In your terminal:
```bash
cd ~/projects/my-api
amp --ide
```

The Amp CLI interface appears, showing it's connected to Emacs.

Enable client notifications:
```
M-x amp-client-enable
```

## Step 2: Explore the Bug

Open the file with the bug:
```
C-x C-f auth.py
```

Amp automatically knows you're looking at `auth.py` now.

**In the Amp CLI, ask:**
```
What does this file do?
```

**Amp responds:**
> This file handles user authentication for the API. It contains functions for validating credentials, 
> generating JWT tokens, and checking user permissions. The main function is `authenticate_user()` 
> which takes a username and password.

## Step 3: Ask About the Specific Bug

Looking at the code, you see the `authenticate_user()` function. Select it with your mouse or keyboard (C-SPACE, move cursor, done).

Press `C-c a e` (amp-explain-region) or use:
```
M-x amp-explain-region
```

**Amp sees your selection and explains:**
> This function validates user credentials by:
> 1. Looking up the user in the database
> 2. Comparing the hashed password
> 3. Returning a JWT token if valid
> 
> I notice a potential issue: if the user doesn't exist, it returns `None` instead of 
> raising an exception, which might cause unclear error messages downstream.

## Step 4: Ask Amp to Suggest a Fix

**In Amp CLI, type:**
```
The bug report says users get unclear error messages when login fails. 
How should I improve the error handling in the selected function?
```

**Amp responds with suggestions:**
> Here's how to improve error handling:
> 
> 1. Add specific exceptions for different failure cases:
>    - UserNotFoundException when user doesn't exist
>    - InvalidPasswordException when password is wrong
> 
> 2. Return clear error messages to the API client
> 
> 3. Log failed attempts for security monitoring
> 
> Would you like me to implement these changes?

## Step 5: Let Amp Fix the Code

**You respond in Amp CLI:**
```
Yes, implement those changes in auth.py
```

**Amp reads the file, thinks, and then:**
- Adds custom exception classes
- Updates the `authenticate_user()` function with proper error handling
- Adds logging statements
- **Directly edits your buffer in Emacs!**

You see the changes appear in your Emacs buffer in real-time!

## Step 6: Review and Test

The code now looks better. But you want to make sure the error messages are actually helpful.

Select the new exception classes and press `C-c a i` (improve-region):

**Amp suggests:**
> These exceptions look good, but I'd recommend adding more context to the error messages.
> Let me update them to include the username in the error message (without exposing 
> sensitive info).

Amp edits the exceptions to include better context.

## Step 7: Write Tests

Now you need tests for the new error handling. Open the test file:
```
C-x C-f tests/test_auth.py
```

**Send a message to Amp:**
```
M-x amp-send-message
```
Type:
```
Write tests for the new error handling in auth.py, covering:
- User not found scenario
- Invalid password scenario  
- Successful login
```

**Amp creates the test file:**

Amp reads `auth.py` to understand the implementation, then creates comprehensive tests 
and saves them directly to `test_auth.py` in Emacs.

## Step 8: Run the Tests

Switch to a terminal in Emacs (`M-x term` or use your terminal):
```bash
pytest tests/test_auth.py -v
```

All tests pass! ✅

## Step 9: Review the Changes Together

You want to make sure everything is good before committing.

**Ask Amp:**
```
Review all the changes we made. Are there any security issues or edge cases we missed?
```

**Amp analyzes the changes:**
> The changes look solid. A few observations:
> 
> ✅ Good: Clear exception hierarchy
> ✅ Good: Proper logging without exposing passwords
> ✅ Good: Comprehensive test coverage
> 
> ⚠️ Consider: Rate limiting for failed login attempts (not in this file, but worth adding)
> ⚠️ Consider: The error messages could reveal if a username exists - might be a 
>    security concern for some applications
> 
> Would you like me to make the error messages more generic for security?

## Step 10: Final Polish

**You decide:**
```
Yes, make the error messages more generic. Use "Invalid credentials" for both 
user not found and wrong password cases.
```

Amp updates the code one more time.

## Step 11: Commit Your Work

Everything looks good! In Emacs:
```
M-x magit-status
```

Or in terminal:
```bash
git add auth.py tests/test_auth.py
git commit -m "Fix authentication error handling

- Add specific exceptions for auth failures
- Improve error messages while maintaining security
- Add comprehensive test coverage
- Add logging for failed login attempts"
```

## Final Result

**What you accomplished with Amp:**

1. ✅ Understood the existing code
2. ✅ Identified the root cause of unclear errors
3. ✅ Implemented proper exception handling
4. ✅ Added security-conscious error messages
5. ✅ Wrote comprehensive tests
6. ✅ Got a security review
7. ✅ Fixed all issues in ~15 minutes

**Files changed:**
- `auth.py` - Better error handling and logging
- `tests/test_auth.py` - Full test coverage

**Without Amp, this might have taken:**
- 30 minutes to understand the code
- 20 minutes to implement the fix
- 30 minutes to write tests
- 15 minutes to review for security issues
- **Total: ~90 minutes**

**With Amp: ~15 minutes** ⚡

## Key Takeaways

### What Made This Efficient:

1. **Context Awareness**: Amp knew what file you were viewing
2. **Selection Understanding**: You could select code and ask about it
3. **Direct Editing**: Amp edited files in your Emacs buffers
4. **Iterative Refinement**: Easy to ask for improvements
5. **Multi-file Understanding**: Amp could read other files for context

### Commands Used:

| Command | What We Used It For |
|---------|-------------------|
| `amp-start` | Start the session |
| `amp-client-enable` | Enable file tracking |
| `C-c a e` (amp-explain-region) | Understand selected code |
| `C-c a i` (amp-improve-region) | Get suggestions for improvement |
| `M-x amp-send-message` | Request specific tasks |

### The Workflow Pattern:

```
1. Open file (Amp sees it)
2. Select code
3. Ask Amp about it (explain, fix, improve)
4. Let Amp edit the file
5. Review changes
6. Iterate as needed
7. Commit
```

## Try It Yourself!

This workflow works for:

- 🐛 **Bug fixing** - Amp helps debug and fix issues
- ✨ **Feature implementation** - Amp scaffolds new features
- 📝 **Documentation** - Amp writes docstrings and README updates
- 🧪 **Testing** - Amp generates test cases
- ♻️ **Refactoring** - Amp helps modernize code
- 🔒 **Security** - Amp reviews for vulnerabilities
- 🎨 **Code style** - Amp applies consistent formatting

## Tips for Effective Amp Usage

### Do:
✅ Give Amp context by opening relevant files
✅ Select specific code sections when asking questions
✅ Ask for explanations before asking for changes
✅ Review Amp's changes before committing
✅ Use `C-c a e` to understand unfamiliar code
✅ Let Amp write repetitive code (tests, boilerplate)

### Don't:
❌ Trust Amp blindly - always review changes
❌ Ask vague questions - be specific
❌ Forget to enable `amp-client-enable`
❌ Skip testing Amp's code
❌ Commit without understanding the changes

## Advanced Techniques

### 1. Cross-file Refactoring

Open both files you want to refactor:
```
C-x C-f models.py
C-x C-f auth.py
```

Then ask Amp to update both to use a new pattern.

### 2. Iterative Debugging

When tests fail:
```bash
pytest tests/ -v
```

Copy error message, then in Amp:
```
The test is failing with this error: [paste error]
What's wrong and how do I fix it?
```

Amp reads the test file and the implementation, then suggests fixes.

### 3. Learning New Code

When joining a new project:
```
Open main file
C-c a e on important functions
Ask: "How does authentication flow work across these files?"
```

Amp becomes your onboarding buddy!

## Conclusion

amp-emacs brings AI pair programming directly into Emacs. It's like having an expert colleague who:
- Never gets tired
- Knows your entire codebase
- Can edit files instantly
- Provides thoughtful suggestions
- Works at the speed of thought

Happy coding! 🚀

---

**Questions or feedback?** Open an issue at https://github.com/yourusername/amp-emacs

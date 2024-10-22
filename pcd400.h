//	pcd400.h

#ifndef __PCD400_H__
#define	__PCD400_H__

#define DLL_EXTERN

// pcd400.dll error code
#define	PCDUSB_ERROR_NONE			0				// No error
#define	PCDUSB_ERROR_NOT_OPEN		(-1)			// DLL is not opened. 
#define	PCDUSB_ERROR_PARAM			(-2)			// Argument of the API function is faulty.
#define	PCDUSB_ERROR_LOCKED			(-3)			// Other processes are in use. 
#define	PCDUSB_ERROR_NO_TARGET		(-100)			// No target PCD exists.
#define	PCDUSB_ERROR_TRANS			(-101)			// Data transfer error (Timeout).
#define PCDUSB_ERROR_EXCEPTION		(-102)			// Internal error (Exception error) occurred.

// Communication timeout value ([seconds]).
#define	PCDUSB_TMO_MAX				60

#ifdef __cplusplus
extern "C" {
#endif

// Export API function
DLL_EXTERN int __stdcall PCD400_UsbOpen(void);
DLL_EXTERN int __stdcall PCD400_UsbClose(void);
DLL_EXTERN int __stdcall PCD400_UsbSetTimeOut(WORD wTimeOut);
DLL_EXTERN int __stdcall PCD400_UsbConnectCheck(WORD *pwConnect);
DLL_EXTERN int __stdcall PCD400_UsbSendCmd(DWORD dwSendByte, const void *pSendCmd);
DLL_EXTERN int __stdcall PCD400_UsbReceiveCmd(void *pReceiveCmd, DWORD dwReceiveSize);
DLL_EXTERN int __stdcall PCD400_UsbTargetReset(void);

#ifdef __cplusplus
}
#endif

#endif	// __PCD400_H__

